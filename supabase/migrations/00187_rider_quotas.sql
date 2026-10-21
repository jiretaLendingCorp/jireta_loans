-- supabase/migrations/00187_rider_quotas.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- RIDER QUOTA MANAGEMENT
--
-- Pinagmumulan ng lahat ng numero:
--   • rider_quotas            → assigned target, period at date window
--   • collection_assignments  → sino ang rider na naka-assign sa installment
--   • payments                → verified collections na ini-attribute sa rider
--                               sa pamamagitan ng `collection_assignment_id`
--
-- MAHALANGANG DESISYON:
--   • Confirmed Collections = SUM(payments.amount) kung saan `status='verified'`
--     AT naka-link sa assignment ng rider at ang `paid_at` (Asia/Manila) ay
--     pumapasok sa [start_date, end_date] ng quota. Hindi binibilang ang
--     pending / rejected / reversed / cancelled. Isang beses lang binibilang
--     ang bawat payment row (ang `idempotency_key` ay UNIQUE sa `payments`).
--   • Ang status (upcoming / active / completed / expired / inactive) ay
--     DERIVED mula sa dates at sa result — hindi ito free-text na label.
--     `is_active=false` lang ang manual na "closed / inactive" (soft close,
--     walang DELETE) para manatili ang history.
--   • Hindi pwedeng mag-overlap ang dalawang ACTIVE na quota ng parehong rider
--     (enforced ng trigger, hindi lang sa app).
--   • Read-only ang computation RPCs (STABLE). Walang penalty, walang wage
--     deduction, walang loan/payment na binabago kapag hindi naabot ang target.
--   • Ang pag-edit ay pinapayagan lang habang upcoming/active ang quota (sa
--     Edge Function), para hindi mababago ang historical record ng tapos nang
--     period. Ang bawat create/update/close ay naka-audit.
--
-- Access: service_role only. Tinatawag ito ng `collections-view` at
-- `collections-manage` Edge Functions pagkatapos i-validate ang role.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Table
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rider_quotas (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id      UUID           NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  period        TEXT           NOT NULL,
  target_amount DECIMAL(12,2)  NOT NULL,
  start_date    DATE           NOT NULL,
  end_date      DATE           NOT NULL,
  notes         TEXT,
  is_active     BOOLEAN        NOT NULL DEFAULT TRUE,
  closed_at     TIMESTAMPTZ,
  closed_by     UUID           REFERENCES public.users(id),
  created_by    UUID           REFERENCES public.users(id),
  updated_by    UUID           REFERENCES public.users(id),
  created_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  CONSTRAINT rider_quotas_period_check
    CHECK (period IN ('daily', 'weekly', 'monthly')),
  CONSTRAINT rider_quotas_target_check
    CHECK (target_amount > 0),
  CONSTRAINT rider_quotas_dates_check
    CHECK (end_date >= start_date),
  CONSTRAINT rider_quotas_notes_len_check
    CHECK (notes IS NULL OR char_length(notes) <= 500)
);

COMMENT ON TABLE public.rider_quotas IS
  'Rider collection quotas (daily/weekly/monthly target). Service-role only. Confirmed collections are computed from verified payments, never stored.';
COMMENT ON COLUMN public.rider_quotas.is_active IS
  'FALSE = manually closed/inactive (soft close). Upcoming/active/completed/expired are derived from the dates and the collected amount.';

CREATE INDEX IF NOT EXISTS idx_rider_quotas_rider_start
  ON public.rider_quotas (rider_id, start_date DESC);
CREATE INDEX IF NOT EXISTS idx_rider_quotas_active_window
  ON public.rider_quotas (rider_id, start_date, end_date)
  WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_rider_quotas_status_window
  ON public.rider_quotas (is_active, start_date, end_date);

DROP TRIGGER IF EXISTS trg_rider_quotas_updated_at ON public.rider_quotas;
CREATE TRIGGER trg_rider_quotas_updated_at
  BEFORE UPDATE ON public.rider_quotas
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Overlap guard — isang ACTIVE quota lang kada rider sa isang petsa.
--    Trigger (hindi app-level) para hindi ito malampasan ng kahit anong
--    write path. Ang sabay na INSERT ay sinalo ng index/trigger sa ilalim ng
--    parehong transaction at row lock ng rider.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_rider_quota_no_overlap()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.is_active THEN
    -- Serialize concurrent writes para sa parehong rider.
    PERFORM pg_advisory_xact_lock(hashtext('rider_quota:' || NEW.rider_id::text));

    IF EXISTS (
      SELECT 1
      FROM public.rider_quotas q
      WHERE q.rider_id = NEW.rider_id
        AND q.is_active
        AND q.id <> NEW.id
        AND daterange(q.start_date, q.end_date, '[]')
            && daterange(NEW.start_date, NEW.end_date, '[]')
    ) THEN
      RAISE EXCEPTION
        'RIDER_QUOTA_OVERLAP: an active quota already covers % to %',
        NEW.start_date, NEW.end_date
        USING ERRCODE = '23505';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rider_quota_no_overlap ON public.rider_quotas;
CREATE TRIGGER trg_rider_quota_no_overlap
  BEFORE INSERT OR UPDATE ON public.rider_quotas
  FOR EACH ROW EXECUTE FUNCTION public.fn_rider_quota_no_overlap();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) RLS / grants
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.rider_quotas ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.rider_quotas FROM PUBLIC;
REVOKE ALL ON TABLE public.rider_quotas FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.rider_quotas TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) HM/Employee monitoring RPC — isang round-trip para sa table + cards.
--
--    p_rider_id  : optional filter
--    p_period    : optional (daily | weekly | monthly)
--    p_status    : all | upcoming | active | completed | expired | inactive
--    p_date_from : optional — quota window na nago-overlap sa range
--    p_date_to   : optional
--    p_search    : optional rider name search
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rider_quota_monitoring(
  p_rider_id  uuid DEFAULT NULL,
  p_period    text DEFAULT NULL,
  p_status    text DEFAULT NULL,
  p_date_from date DEFAULT NULL,
  p_date_to   date DEFAULT NULL,
  p_search    text DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
WITH params AS (
  SELECT
    p_rider_id                              AS rider_id,
    NULLIF(btrim(COALESCE(p_period, '')), '') AS period,
    COALESCE(NULLIF(btrim(COALESCE(p_status, '')), ''), 'all') AS status,
    p_date_from                             AS date_from,
    p_date_to                               AS date_to,
    NULLIF(btrim(COALESCE(p_search, '')), '') AS search
),
rider_base AS (
  SELECT
    q.id, q.rider_id, q.period, q.target_amount, q.start_date, q.end_date,
    q.notes, q.is_active, q.created_by, q.created_at, q.updated_at,
    u.first_name, u.last_name, u.phone_number,
    btrim(COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')) AS rider_name,
    (now_manila())::date AS today
  FROM public.rider_quotas q
  JOIN public.users u ON u.id = q.rider_id
  JOIN public.roles r ON r.id = u.role_id AND r.name = 'rider'
  CROSS JOIN params p
  WHERE (p.rider_id IS NULL OR q.rider_id = p.rider_id)
    AND (p.period IS NULL OR q.period = p.period)
    AND (
      p.search IS NULL
      OR (COALESCE(u.first_name, '') || ' ' || COALESCE(u.last_name, '')) ILIKE '%' || p.search || '%'
    )
    AND (p.date_from IS NULL OR q.end_date >= p.date_from)
    AND (p.date_to IS NULL OR q.start_date <= p.date_to)
),
collected AS (
  SELECT
    rb.id AS quota_id,
    COALESCE(SUM(pay.amount), 0) AS confirmed,
    COUNT(pay.id)                AS payment_count,
    MAX(pay.paid_at)             AS last_paid_at
  FROM rider_base rb
  LEFT JOIN public.collection_assignments ca
    ON ca.rider_id = rb.rider_id
  LEFT JOIN public.payments pay
    ON pay.collection_assignment_id = ca.id
   AND pay.status = 'verified'
   AND (pay.paid_at AT TIME ZONE 'Asia/Manila')::date BETWEEN rb.start_date AND rb.end_date
  GROUP BY rb.id
),
calc AS (
  SELECT
    rb.*,
    COALESCE(cf.confirmed, 0)     AS confirmed,
    COALESCE(cf.payment_count, 0) AS payment_count,
    cf.last_paid_at,
    GREATEST(rb.target_amount - COALESCE(cf.confirmed, 0), 0) AS remaining,
    CASE
      WHEN rb.target_amount > 0
        THEN ROUND(COALESCE(cf.confirmed, 0) / rb.target_amount * 100, 2)
      ELSE NULL
    END AS completion,
    (COALESCE(cf.confirmed, 0) >= rb.target_amount) AS achieved,
    CASE
      WHEN NOT rb.is_active THEN 'inactive'
      WHEN rb.today < rb.start_date THEN 'upcoming'
      WHEN rb.today > rb.end_date THEN
        CASE WHEN COALESCE(cf.confirmed, 0) >= rb.target_amount THEN 'completed' ELSE 'expired' END
      ELSE 'active'
    END AS derived_status
  FROM rider_base rb
  LEFT JOIN collected cf ON cf.quota_id = rb.id
),
filtered AS (
  SELECT c.*
  FROM calc c
  CROSS JOIN params p
  WHERE p.status = 'all' OR c.derived_status = p.status
),
summary AS (
  SELECT
    (SELECT COUNT(DISTINCT rider_id) FROM filtered WHERE derived_status = 'active')          AS active_riders,
    (SELECT COALESCE(SUM(target_amount), 0) FROM filtered WHERE derived_status = 'active')    AS assigned_quota,
    (SELECT COALESCE(SUM(confirmed), 0) FROM filtered WHERE derived_status = 'active')        AS confirmed_total,
    (SELECT COALESCE(SUM(remaining), 0) FROM filtered WHERE derived_status = 'active')        AS remaining_total,
    (SELECT COUNT(DISTINCT rider_id) FROM filtered WHERE achieved)                            AS riders_met,
    (SELECT COUNT(*) FROM filtered WHERE derived_status IN ('active', 'upcoming'))            AS open_quotas,
    (SELECT COUNT(*) FROM filtered)                                                           AS total_quotas,
    (SELECT COUNT(*) FROM filtered WHERE derived_status = 'expired')                          AS expired_quotas
)
SELECT jsonb_build_object(
  'rows', COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'quota_id',              f.id,
        'rider_id',              f.rider_id,
        'rider_name',            NULLIF(f.rider_name, ''),
        'phone_number',          f.phone_number,
        'period',                f.period,
        'target_amount',         f.target_amount,
        'confirmed_collection',  f.confirmed,
        'remaining_target',      f.remaining,
        'completion_percentage', f.completion,
        'start_date',            f.start_date,
        'end_date',              f.end_date,
        'status',                f.derived_status,
        'is_active',             f.is_active,
        'achieved',              f.achieved,
        'payment_count',         f.payment_count,
        'last_paid_at',          f.last_paid_at,
        'notes',                 f.notes,
        'created_at',            f.created_at,
        'updated_at',            f.updated_at
      )
      ORDER BY f.start_date DESC, f.rider_name
    )
    FROM filtered f
  ), '[]'::jsonb),
  'summary', (
    SELECT jsonb_build_object(
      'active_riders',   s.active_riders,
      'assigned_quota',  s.assigned_quota,
      'confirmed_total', s.confirmed_total,
      'remaining_total', s.remaining_total,
      'riders_met',      s.riders_met,
      'open_quotas',     s.open_quotas,
      'total_quotas',    s.total_quotas,
      'expired_quotas',  s.expired_quotas
    )
    FROM summary s
  ),
  'generated_at', NOW()
);
$fn$;

COMMENT ON FUNCTION public.rider_quota_monitoring(uuid, text, text, date, date, text) IS
  'Rider quota rows + summary cards. Confirmed collections come from verified payments only. SERVICE ROLE ONLY.';

REVOKE ALL ON FUNCTION public.rider_quota_monitoring(uuid, text, text, date, date, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rider_quota_monitoring(uuid, text, text, date, date, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rider_quota_monitoring(uuid, text, text, date, date, text) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) Rider self RPC — current quota, previous results at ang mga verified
--    payment na bumubuo sa current quota. Ang `p_rider_id` ay LAGING galing sa
--    token sa Edge Function (hindi kailanman sa query string).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rider_quota_self(p_rider_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
WITH base AS (
  SELECT
    q.*,
    (now_manila())::date AS today
  FROM public.rider_quotas q
  WHERE q.rider_id = p_rider_id
),
collected AS (
  SELECT
    b.id AS quota_id,
    COALESCE(SUM(pay.amount), 0) AS confirmed,
    COUNT(pay.id)                AS payment_count
  FROM base b
  LEFT JOIN public.collection_assignments ca ON ca.rider_id = b.rider_id
  LEFT JOIN public.payments pay
    ON pay.collection_assignment_id = ca.id
   AND pay.status = 'verified'
   AND (pay.paid_at AT TIME ZONE 'Asia/Manila')::date BETWEEN b.start_date AND b.end_date
  GROUP BY b.id
),
calc AS (
  SELECT
    b.*,
    COALESCE(c.confirmed, 0)     AS confirmed,
    COALESCE(c.payment_count, 0) AS payment_count,
    GREATEST(b.target_amount - COALESCE(c.confirmed, 0), 0) AS remaining,
    CASE
      WHEN b.target_amount > 0
        THEN ROUND(COALESCE(c.confirmed, 0) / b.target_amount * 100, 2)
      ELSE NULL
    END AS completion,
    (COALESCE(c.confirmed, 0) >= b.target_amount) AS achieved,
    CASE
      WHEN NOT b.is_active THEN 'inactive'
      WHEN b.today < b.start_date THEN 'upcoming'
      WHEN b.today > b.end_date THEN
        CASE WHEN COALESCE(c.confirmed, 0) >= b.target_amount THEN 'completed' ELSE 'expired' END
      ELSE 'active'
    END AS derived_status
  FROM base b
  LEFT JOIN collected c ON c.quota_id = b.id
),
current_q AS (
  SELECT * FROM calc
  WHERE derived_status IN ('active', 'upcoming')
  ORDER BY CASE derived_status WHEN 'active' THEN 0 ELSE 1 END, start_date ASC
  LIMIT 1
)
SELECT jsonb_build_object(
  'current', (
    SELECT jsonb_build_object(
      'quota_id',              cq.id,
      'period',                cq.period,
      'target_amount',         cq.target_amount,
      'confirmed_collection',  cq.confirmed,
      'remaining_target',      cq.remaining,
      'completion_percentage', cq.completion,
      'start_date',            cq.start_date,
      'end_date',              cq.end_date,
      'status',                cq.derived_status,
      'achieved',              cq.achieved,
      'payment_count',         cq.payment_count,
      'notes',                 cq.notes
    )
    FROM current_q cq
  ),
  'history', COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'quota_id',              h.id,
        'period',                h.period,
        'target_amount',         h.target_amount,
        'confirmed_collection',  h.confirmed,
        'remaining_target',      h.remaining,
        'completion_percentage', h.completion,
        'start_date',            h.start_date,
        'end_date',              h.end_date,
        'status',                h.derived_status,
        'achieved',              h.achieved,
        'payment_count',         h.payment_count
      )
      ORDER BY h.start_date DESC
    )
    FROM calc h
    WHERE h.derived_status NOT IN ('active', 'upcoming')
  ), '[]'::jsonb),
  'payments', COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'payment_id',         pay.id,
        'amount',             pay.amount,
        'paid_at',            pay.paid_at,
        'payment_method',     pay.payment_method,
        'assignment_id',      ca.id,
        'loan_number',        l.loan_number,
        'installment_number', ls.installment_number
      )
      ORDER BY pay.paid_at DESC
    )
    FROM current_q cq
    JOIN public.collection_assignments ca ON ca.rider_id = p_rider_id
    JOIN public.payments pay
      ON pay.collection_assignment_id = ca.id
     AND pay.status = 'verified'
     AND (pay.paid_at AT TIME ZONE 'Asia/Manila')::date BETWEEN cq.start_date AND cq.end_date
    LEFT JOIN public.loan_schedules ls ON ls.id = ca.loan_schedule_id
    LEFT JOIN public.loans l ON l.id = ls.loan_id
  ), '[]'::jsonb),
  'generated_at', NOW()
);
$fn$;

COMMENT ON FUNCTION public.rider_quota_self(uuid) IS
  'Rider current quota + previous results + verified payments inside the current quota window. SERVICE ROLE ONLY.';

REVOKE ALL ON FUNCTION public.rider_quota_self(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rider_quota_self(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rider_quota_self(uuid) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6) Realtime — para agad mag-refresh ang HM quota page at rider My Quota kapag
--    may bagong assignment/edit/close.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = 'rider_quotas'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.rider_quotas;
  END IF;
END $$;

COMMIT;
