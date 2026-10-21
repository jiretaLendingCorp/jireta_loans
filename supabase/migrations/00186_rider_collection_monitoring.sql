-- supabase/migrations/00186_rider_collection_monitoring.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- RIDER COLLECTION MONITORING — read-only aggregation layer.
--
-- Pinagmumulan ng lahat ng numero:
--   • collection_assignments  → sino ang rider na naka-assign sa installment
--   • loan_schedules          → kung magkano ang due at kailan
--   • v_loan_schedules        → verified (approved) na bayad kada installment
--   • payments                → confirmed na koleksyon, ini-attribute sa rider
--                               sa pamamagitan ng `collection_assignment_id`
--
-- MAHALAGANG DESISYON:
--   • `confirmed` = verified payments LANG na naka-link sa assignment ng rider.
--     Hindi binibilang ang pending / rejected / reversed. Ang office cash at
--     GCash na walang assignment ay hindi kayang i-attribute sa rider, kaya
--     hindi ito idinadagdag sa rider total (hindi ito double-count).
--   • `remaining` = amount_due − amount_paid mula sa canonical na
--     `v_loan_schedules` (kunin ang totoong installment balance, kasama ang
--     partial payments at penalties na naka-allocate na).
--   • `expected` at `remaining` ay DEDUPED per rider + loan_schedule. Kapag
--     dalawang beses na-assign ang parehong installment (hal. na-reassign),
--     isang beses lang ito binibilang.
--   • Ang summary ay nagde-dedupe din ACROSS riders para hindi doble ang
--     assigned accounts / expected / remaining kapag may shared schedule.
--   • Walang quota sa feature na ito. Ang `collection_performance` ay
--     confirmed ÷ expected — monitoring indicator lamang, hindi target.
--   • Read-only: walang INSERT/UPDATE, walang penalty, walang status change.
--
-- Access: service_role only (tinatawag ng `collections-view` Edge Function pag-
-- katapos i-validate ang role). Hindi ito naka-expose sa anon/authenticated at
-- hindi nito binabago ang RLS ng mga base table.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Per-assignment monitoring rows.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_rider_collection_monitoring AS
SELECT
  ca.id                                  AS assignment_id,
  ca.rider_id,
  ca.loan_schedule_id,
  ca.status                              AS assignment_status,
  ca.collection_type,
  ca.collection_schedule,
  ca.amount_collected,
  ca.completed_at,
  ca.created_at                          AS assigned_at,
  s.loan_id,
  s.installment_number,
  s.due_date,
  s.amount_due,
  COALESCE(vs.amount_paid, 0)            AS schedule_paid,
  vs.status                              AS schedule_status,
  vs.paid_at                             AS schedule_paid_at,
  COALESCE(ap.confirmed_amount, 0)       AS assignment_confirmed,
  ap.last_confirmed_at
FROM public.collection_assignments ca
JOIN public.loan_schedules s
  ON s.id = ca.loan_schedule_id
LEFT JOIN public.v_loan_schedules vs
  ON vs.id = s.id
LEFT JOIN LATERAL (
  SELECT
    SUM(p.amount)     AS confirmed_amount,
    MAX(p.paid_at)    AS last_confirmed_at
  FROM public.payments p
  WHERE p.collection_assignment_id = ca.id
    AND p.status = 'verified'
) ap ON TRUE;

COMMENT ON VIEW public.v_rider_collection_monitoring IS
  'Read-only monitoring rows: assignment + installment due/paid + verified confirmed amount per assignment. Service-role only.';

REVOKE ALL ON public.v_rider_collection_monitoring FROM PUBLIC;
REVOKE ALL ON public.v_rider_collection_monitoring FROM anon, authenticated;
GRANT SELECT ON public.v_rider_collection_monitoring TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Aggregation RPC — isang round-trip para sa monitoring table at summary.
--
--    p_rider_id   : optional na filter (ginagamit din ng detail page)
--    p_date_from  : optional (YYYY-MM-DD) — due date ng installment at petsa ng
--                   confirmed payment (Asia/Manila)
--    p_date_to    : optional (YYYY-MM-DD)
--    p_search     : optional rider name search
--    p_status     : all | active | overdue | has_collection | no_collection
--
--    Ang `rows` ay hindi pa naka-paginate — maliit lang ang bilang ng rider at
--    ang Edge Function ang nagso-sort/paginate para isang beses lang ang
--    aggregation. Ang `summary` ay laging deduped at hindi apektado ng
--    `p_status` (filter lang iyon ng table).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rider_collection_monitoring(
  p_rider_id  uuid DEFAULT NULL,
  p_date_from date DEFAULT NULL,
  p_date_to   date DEFAULT NULL,
  p_search    text DEFAULT NULL,
  p_status    text DEFAULT 'all'
) RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
WITH params AS (
  SELECT
    p_rider_id                              AS rider_id,
    p_date_from                             AS date_from,
    p_date_to                               AS date_to,
    NULLIF(btrim(COALESCE(p_search, '')), '') AS search,
    COALESCE(NULLIF(btrim(COALESCE(p_status, '')), ''), 'all') AS status
),
rider_base AS (
  SELECT
    u.id                                        AS rider_id,
    btrim(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')) AS rider_name,
    u.phone_number,
    u.created_at                                AS joined_at,
    rp.plate_number,
    rp.vehicle_type,
    rp.is_available
  FROM public.users u
  JOIN public.roles r          ON r.id = u.role_id
  JOIN public.rider_profiles rp ON rp.id = u.id
  CROSS JOIN params p
  WHERE r.name = 'rider'
    AND u.account_status = 'active'
    AND (p.rider_id IS NULL OR u.id = p.rider_id)
    AND (
      p.search IS NULL
      OR (COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')) ILIKE '%' || p.search || '%'
    )
),
scoped AS (
  SELECT m.*
  FROM public.v_rider_collection_monitoring m
  JOIN rider_base rb ON rb.rider_id = m.rider_id
  CROSS JOIN params p
  WHERE (p.date_from IS NULL OR m.due_date >= p.date_from)
    AND (p.date_to   IS NULL OR m.due_date <= p.date_to)
),
-- Isang row kada rider + installment. Ang pinakabagong assignment ang
-- pinipili, pero schedule-level ang mga field na binabasa kaya hindi ito
-- nagbabago ng halaga.
sched AS (
  SELECT DISTINCT ON (s.rider_id, s.loan_schedule_id)
    s.rider_id,
    s.loan_id,
    s.loan_schedule_id,
    s.due_date,
    s.amount_due,
    s.schedule_paid,
    s.schedule_status
  FROM scoped s
  ORDER BY s.rider_id, s.loan_schedule_id, s.assigned_at DESC
),
confirmed AS (
  SELECT
    ca.rider_id,
    SUM(pay.amount)  AS confirmed,
    COUNT(*)         AS payment_count,
    MAX(pay.paid_at) AS last_paid_at
  FROM public.payments pay
  JOIN public.collection_assignments ca ON ca.id = pay.collection_assignment_id
  JOIN rider_base rb                    ON rb.rider_id = ca.rider_id
  CROSS JOIN params p
  WHERE pay.status = 'verified'
    AND (p.date_from IS NULL OR (pay.paid_at AT TIME ZONE 'Asia/Manila')::date >= p.date_from)
    AND (p.date_to   IS NULL OR (pay.paid_at AT TIME ZONE 'Asia/Manila')::date <= p.date_to)
  GROUP BY ca.rider_id
),
activity AS (
  SELECT
    ca.rider_id,
    MAX(GREATEST(ca.completed_at, ca.created_at)) AS last_assignment_activity
  FROM public.collection_assignments ca
  JOIN rider_base rb ON rb.rider_id = ca.rider_id
  GROUP BY ca.rider_id
),
open_assign AS (
  SELECT ca.rider_id, COUNT(*) AS open_assignments
  FROM public.collection_assignments ca
  JOIN rider_base rb ON rb.rider_id = ca.rider_id
  WHERE ca.status IN ('requested', 'assigned', 'accepted', 'in_progress')
  GROUP BY ca.rider_id
),
rider_rows AS (
  SELECT
    rb.rider_id,
    rb.rider_name,
    rb.phone_number,
    rb.joined_at,
    rb.plate_number,
    rb.vehicle_type,
    rb.is_available,
    COALESCE(sc.assigned_accounts, 0)       AS assigned_accounts,
    COALESCE(sc.assigned_installments, 0)   AS assigned_installments,
    COALESCE(sc.expected, 0)                AS expected_collection,
    COALESCE(sc.remaining, 0)               AS remaining_due,
    COALESCE(sc.overdue_accounts, 0)        AS overdue_accounts,
    COALESCE(sc.overdue_installments, 0)    AS overdue_installments,
    sc.next_due_date,
    COALESCE(cf.confirmed, 0)               AS confirmed_collection,
    COALESCE(cf.payment_count, 0)           AS confirmed_payment_count,
    COALESCE(oa.open_assignments, 0)        AS open_assignments,
    GREATEST(act.last_assignment_activity, cf.last_paid_at) AS last_activity_at,
    CASE
      WHEN COALESCE(sc.expected, 0) > 0
        THEN ROUND(COALESCE(cf.confirmed, 0) / COALESCE(sc.expected, 0) * 100, 1)
      ELSE NULL
    END                                     AS collection_performance
  FROM rider_base rb
  LEFT JOIN (
    SELECT
      rider_id,
      COUNT(DISTINCT loan_id)                                        AS assigned_accounts,
      COUNT(*)                                                       AS assigned_installments,
      SUM(amount_due)                                                AS expected,
      SUM(GREATEST(amount_due - schedule_paid, 0))                   AS remaining,
      COUNT(DISTINCT loan_id) FILTER (WHERE schedule_status = 'overdue') AS overdue_accounts,
      COUNT(*)                FILTER (WHERE schedule_status = 'overdue') AS overdue_installments,
      MIN(due_date)           FILTER (WHERE schedule_status <> 'paid')   AS next_due_date
    FROM sched
    GROUP BY rider_id
  ) sc ON sc.rider_id = rb.rider_id
  LEFT JOIN confirmed cf   ON cf.rider_id = rb.rider_id
  LEFT JOIN activity act   ON act.rider_id = rb.rider_id
  LEFT JOIN open_assign oa ON oa.rider_id = rb.rider_id
),
filtered AS (
  SELECT r.*
  FROM rider_rows r
  CROSS JOIN params p
  WHERE p.status = 'all'
     OR (p.status = 'active'         AND r.open_assignments > 0)
     OR (p.status = 'overdue'        AND r.overdue_accounts > 0)
     OR (p.status = 'has_collection' AND r.confirmed_collection > 0)
     OR (p.status = 'no_collection'  AND r.confirmed_collection = 0)
),
summary AS (
  SELECT
    (SELECT COUNT(*) FROM rider_rows)                                   AS active_riders,
    (SELECT COUNT(DISTINCT loan_id) FROM sched)                         AS assigned_accounts,
    (SELECT COUNT(*) FROM sched)                                        AS assigned_installments,
    (SELECT COALESCE(SUM(amount_due), 0) FROM sched)                    AS expected_collection,
    (SELECT COALESCE(SUM(confirmed), 0) FROM confirmed)                 AS confirmed_collection,
    (SELECT COALESCE(SUM(GREATEST(amount_due - schedule_paid, 0)), 0) FROM sched) AS remaining_due,
    (SELECT COUNT(DISTINCT loan_id) FROM sched WHERE schedule_status = 'overdue') AS overdue_accounts,
    (SELECT COUNT(*) FROM sched WHERE schedule_status = 'overdue')       AS overdue_installments,
    (SELECT COALESCE(SUM(open_assignments), 0) FROM open_assign)         AS open_assignments,
    (SELECT COUNT(*) FROM confirmed)                                    AS confirmed_payment_count
)
SELECT jsonb_build_object(
  'rows', COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'rider_id',                f.rider_id,
        'rider_name',              NULLIF(f.rider_name, ''),
        'phone_number',            f.phone_number,
        'joined_at',               f.joined_at,
        'plate_number',            f.plate_number,
        'vehicle_type',            f.vehicle_type,
        'is_available',            f.is_available,
        'assigned_accounts',       f.assigned_accounts,
        'assigned_installments',   f.assigned_installments,
        'expected_collection',     f.expected_collection,
        'confirmed_collection',    f.confirmed_collection,
        'remaining_due',           f.remaining_due,
        'overdue_accounts',        f.overdue_accounts,
        'overdue_installments',    f.overdue_installments,
        'open_assignments',        f.open_assignments,
        'next_due_date',           f.next_due_date,
        'last_activity_at',        f.last_activity_at,
        'collection_performance',  f.collection_performance
      )
      ORDER BY f.rider_name
    )
    FROM filtered f
  ), '[]'::jsonb),
  'summary', (
    SELECT jsonb_build_object(
      'active_riders',            s.active_riders,
      'assigned_accounts',        s.assigned_accounts,
      'assigned_installments',    s.assigned_installments,
      'expected_collection',      s.expected_collection,
      'confirmed_collection',     s.confirmed_collection,
      'remaining_due',            s.remaining_due,
      'overdue_accounts',         s.overdue_accounts,
      'overdue_installments',     s.overdue_installments,
      'open_assignments',         s.open_assignments,
      'confirmed_payment_count',  s.confirmed_payment_count
    )
    FROM summary s
  ),
  'generated_at', NOW()
);
$fn$;

COMMENT ON FUNCTION public.rider_collection_monitoring(uuid, date, date, text, text) IS
  'Aggregated rider collection monitoring rows + summary. Read-only. SERVICE ROLE ONLY.';

REVOKE ALL ON FUNCTION public.rider_collection_monitoring(uuid, date, date, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rider_collection_monitoring(uuid, date, date, text, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rider_collection_monitoring(uuid, date, date, text, text) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Report template — Rider Collection Summary.
--    Ang row set ay galing sa parehong RPC, kaya nagre-reconcile ang report
--    sa monitoring page (expected vs confirmed vs remaining).
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.report_templates
  (template_key, title, description, parameters_schema)
VALUES (
  'rider_collection_summary',
  'Rider Collection Summary Report',
  'Expected vs confirmed collections, outstanding balances, and overdue accounts per rider',
  '{"date_from":{"type":"date","optional":true},"date_to":{"type":"date","optional":true},"rider_id":{"type":"uuid","optional":true}}'
)
ON CONFLICT (template_key) DO NOTHING;

COMMIT;
