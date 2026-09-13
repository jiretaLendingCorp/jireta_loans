-- supabase/migrations/00159_collection_balance_gate.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Business rule: ang rider-submitted collection ay naka-record na bilang
-- `verified` payment, PERO hindi pa ito binibilang sa loan balance hangga't
-- hindi ina-approve ng Head Manager/Employee (`fn=approve`, → status
-- `completed`). Kapag ni-reject, `rejected` ang collection at payment, kaya
-- wala ring epekto sa balance.
--
-- Dito sa view inaalis ang verified payments na naka-link sa isang
-- `pending_approval` o `rejected` na koleksyon. Ang direct payments (Xendit /
-- office cash, walang collection_assignment_id) ay nananatiling binibilang.
--
-- KAPAREHAS nito ang lohika sa `_shared/loan_financials.ts`
-- (sumVerifiedPaymentsByLoan / getSchedulePayment) — kailangang pareho sila.
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
  SELECT
    pay.loan_schedule_id,
    SUM(pay.amount) AS amount_paid,
    MAX(pay.paid_at) AS last_paid_at
  FROM payments pay
  LEFT JOIN collection_assignments ca
    ON ca.id = pay.collection_assignment_id
  WHERE pay.status = 'verified'
    AND (ca.status IS NULL OR ca.status NOT IN ('pending_approval', 'rejected'))
  GROUP BY pay.loan_schedule_id
) p ON p.loan_schedule_id = s.id;

ALTER VIEW public.v_loan_schedules SET (security_invoker = true);

GRANT SELECT ON public.v_loan_schedules TO authenticated;
GRANT SELECT ON public.v_loan_schedules TO service_role;

COMMIT;
