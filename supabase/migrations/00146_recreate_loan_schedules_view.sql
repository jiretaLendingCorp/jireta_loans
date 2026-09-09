-- supabase/migrations/00146_recreate_loan_schedules_view.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- The remote database is missing the v_loan_schedules view even though
-- migration 00120 (which created it) is recorded in supabase_migrations.
-- The schema drifted (views were dropped at some point), which silently broke:
--   • loans-view get-details  → loan_schedules: []  → "No schedule generated yet"
--     shown in the HM/Employee loan application details modal (and the lender
--     schedule screens) even for ACTIVE loans with rows in loan_schedules.
--   • loans-view list         → due_date always null
--   • allocatePayment         → no schedules to allocate against → payments fail
--
-- This migration restores the view idempotently (CREATE OR REPLACE) so the
-- remote matches the canonical definition from 00120 (Manila-time overdue
-- check). v_loan_financials is not queried by any edge function, so only
-- v_loan_schedules is recreated here.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

CREATE OR REPLACE VIEW public.v_loan_schedules AS
SELECT
  s.id,
  s.loan_id,
  s.installment_number,
  s.due_date,
  s.amount_due,
  COALESCE(p.amount_paid, 0) AS amount_paid,
  CASE
    WHEN COALESCE(p.amount_paid, 0) >= s.amount_due THEN 'paid'
    WHEN COALESCE(p.amount_paid, 0) > 0 THEN 'partial'
    WHEN s.due_date < (now_manila())::date THEN 'overdue'
    ELSE 'pending'
  END AS status,
  p.last_paid_at AS paid_at,
  s.created_at,
  s.updated_at
FROM loan_schedules s
LEFT JOIN (
  SELECT loan_schedule_id, SUM(amount) AS amount_paid, MAX(paid_at) AS last_paid_at
  FROM payments
  WHERE status = 'verified'
  GROUP BY loan_schedule_id
) p ON p.loan_schedule_id = s.id;

ALTER VIEW public.v_loan_schedules SET (security_invoker = true);

GRANT SELECT ON public.v_loan_schedules TO authenticated;
GRANT SELECT ON public.v_loan_schedules TO service_role;

COMMIT;