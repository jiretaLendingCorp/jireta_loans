-- supabase/migrations/00150_schedule_overdue_only_when_active.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Overdue sa schedule dapat magsimula lang kapag ACTIVE na ang loan.
--
-- Dati: v_loan_schedules marks 'overdue' kapag due_date < today kahit
-- pending/approved pa lang ang loan — kaya pula na agad ang Payment Schedule
-- preview sa Loan Application Details kahit hindi pa na-di-disburse ang loan.
--
-- Ngayon: 'overdue' lang kapag ang parent loan ay 'active' o 'overdue'
-- (consistent sa auto_mark_overdue_loans() na active → overdue lang ang
-- ginagalaw). Pre-release loans (pending … approved) laging 'pending' ang
-- unpaid rows.
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
    WHEN s.due_date < (now_manila())::date
      AND l.status IN ('active', 'overdue') THEN 'overdue'
    ELSE 'pending'
  END AS status,
  p.last_paid_at AS paid_at,
  s.created_at,
  s.updated_at
FROM loan_schedules s
JOIN loans l ON l.id = s.loan_id
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
