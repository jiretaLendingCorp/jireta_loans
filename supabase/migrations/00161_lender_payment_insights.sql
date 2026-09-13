-- 00161_lender_payment_insights.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Per-lender payment insights para sa Head Manager at Employee:
--
--   • outstanding_balance    — CURRENT outstanding balance ng lender (sum ng
--                              outstanding_balance ng active/overdue loans niya).
--                              Ang `approved` (hindi pa na-release) ay hindi
--                              kasama dahil wala pang balance ito.
--   • is_early_payer         — TRUE kapag may verified payment ang lender AT
--                              LAHAT ng verified payments niya ay binayaran
--                              BAGO o sa exactong due date ng installment
--                              (base sa loan term na kinuha niya).
--   • max_days_early         — pinakamalaking bilang ng araw na nauna ang bayad
--                              kaysa sa due date (0 kapag on-time lang).
--
-- Isang round trip lang ito para sa buong page ng lender list (imbes na
-- per-lender queries), kaya hindi bumibigat ang listahan.
--
-- Tandaan: ang internal CTE aliases ay hindi ginagamitan ng pangalan ng OUT
-- parameters (lender_id / outstanding_balance / …) para iwasan ang
-- "column reference is ambiguous" sa SQL-language function.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.lender_payment_insights(p_lender_ids UUID[])
RETURNS TABLE (
  lender_id              UUID,
  outstanding_balance    NUMERIC,
  active_loans_count     INT,
  settled_loans_count    INT,
  verified_payment_count INT,
  on_time_payment_count  INT,
  late_payment_count     INT,
  max_days_early         INT,
  is_early_payer         BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
WITH target_loans AS (
  SELECT
    l.id AS loan_id,
    l.lender_id AS lender_key,
    l.status,
    -- Canonical outstanding balance — pareho ng formula ng
    -- public.loan_outstanding_balance() (00151) pero INLINE para hindi
    -- umasa ang migration na ito sa 00151/00152: ang loans table ay 3NF
    -- na (00021), kaya WALANG loans.outstanding_balance / total_payable
    -- column — derived ito mula sa principal + interest + penalties -
    -- verified payments.
    GREATEST(0, ROUND(
        l.principal_amount * (1 + COALESCE(l.interest_rate, 20) / 100)
      + COALESCE((SELECT SUM(pl.penalty_amount) FROM penalty_logs pl
                  WHERE pl.loan_id = l.id), 0)
      - COALESCE((SELECT SUM(p.amount)
                  FROM payments p
                  JOIN loan_schedules ls ON ls.id = p.loan_schedule_id
                  WHERE ls.loan_id = l.id AND p.status = 'verified'), 0)
    , 2)) AS out_balance
  FROM loans l
  WHERE l.lender_id = ANY(p_lender_ids)
),
loan_agg AS (
  SELECT
    tl.lender_key,
    COALESCE(SUM(CASE WHEN tl.status IN ('active', 'overdue')
                      THEN tl.out_balance ELSE 0 END), 0) AS out_bal,
    COUNT(*) FILTER (WHERE tl.status IN ('active', 'overdue'))::int AS active_cnt,
    COUNT(*) FILTER (WHERE tl.status = 'completed')::int AS settled_cnt
  FROM target_loans tl
  GROUP BY tl.lender_key
),
payment_rows AS (
  -- Manila calendar date ang basehan: ang bayad sa mismong araw ng due date
  -- (kahit 11:59 PM Manila) ay ON TIME, hindi late.
  SELECT
    tl.lender_key,
    s.due_date AS sched_due,
    (p.paid_at AT TIME ZONE 'Asia/Manila')::date AS paid_on
  FROM target_loans tl
  JOIN loan_schedules s ON s.loan_id = tl.loan_id
  JOIN payments p ON p.loan_schedule_id = s.id
  WHERE p.status = 'verified'
),
payment_agg AS (
  SELECT
    pr.lender_key,
    COUNT(*)::int AS paid_cnt,
    COUNT(*) FILTER (WHERE pr.paid_on <= pr.sched_due)::int AS ontime_cnt,
    COUNT(*) FILTER (WHERE pr.paid_on > pr.sched_due)::int AS late_cnt,
    MAX(pr.sched_due - pr.paid_on)::int AS max_early
  FROM payment_rows pr
  GROUP BY pr.lender_key
)
SELECT
  ids.lid,
  COALESCE(la.out_bal, 0)::numeric,
  COALESCE(la.active_cnt, 0)::int,
  COALESCE(la.settled_cnt, 0)::int,
  COALESCE(pa.paid_cnt, 0)::int,
  COALESCE(pa.ontime_cnt, 0)::int,
  COALESCE(pa.late_cnt, 0)::int,
  GREATEST(COALESCE(pa.max_early, 0), 0)::int,
  -- Early payer: may bayad na, at WALANG ni isang late payment.
  (COALESCE(pa.paid_cnt, 0) > 0 AND COALESCE(pa.late_cnt, 0) = 0) AS early
FROM unnest(p_lender_ids) AS ids(lid)
LEFT JOIN loan_agg la ON la.lender_key = ids.lid
LEFT JOIN payment_agg pa ON pa.lender_key = ids.lid;
$$;

COMMENT ON FUNCTION public.lender_payment_insights(UUID[]) IS
  'Per-lender current outstanding balance + early-payer detection (all verified payments on/before their installment due date). Used by HM/Employee lender list and lender details.';

-- service_role lang: ang Edge Function (users-admin / users-manage) ang
-- tumatawag nito pagkatapos i-verify na Head Manager o Employee ang caller.
-- Hindi ito binibigyan ng access sa `authenticated` para hindi mabasa ng
-- lender ang balance ng ibang lender sa pamamagitan ng direct RPC.
GRANT EXECUTE ON FUNCTION public.lender_payment_insights(UUID[]) TO service_role;

REVOKE ALL ON FUNCTION public.lender_payment_insights(UUID[]) FROM PUBLIC;
