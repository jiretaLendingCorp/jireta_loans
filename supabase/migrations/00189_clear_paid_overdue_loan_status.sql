-- supabase/migrations/00189_clear_paid_overdue_loan_status.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Isang beses na paglilinis ng lumang data: may mga loan na naka-`overdue`
-- pa rin kahit bayad na ang lumampas nang installment (o bayad na lahat).
--
-- Dati kasing `overdue` → `completed` lang ang ginagalaw pagkatapos ng bayad,
-- kaya hindi bumabalik sa `active` ang loan kahit wala nang overdue — kita pa
-- rin itong "Overdue" sa Loan Records ng Head Manager at Employee kahit
-- nakabayad na ang lender. Ang edge functions
-- (`_shared/loan_financials.ts: syncLoanStatusAfterPayment`) ay inayos na para
-- hindi na ito mangyari muli; ito ang nag-aayos ng mga row na nauna nang
-- na-stuck.
--
-- Alituntunin (kapareho ng `statusAfterPayment`):
--   • ubos na ang balanse           → `completed`
--   • wala nang overdue installment → `active`
--   • may overdue pa                → `overdue` (hindi ginagalaw)
--
-- Ang binibilang na bayad ay kapareho ng app: verified payments na naka-link
-- sa schedule, kasama ang fallback sa collection assignment, at hindi
-- binibilang ang koleksyong `pending_approval`/`rejected`.
-- Idempotent: safe i-rerun.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

WITH effective AS (
  -- (a) payment → loan_schedule (normal na allocation)
  SELECT DISTINCT
         p.id                AS payment_id,
         s.loan_id           AS loan_id,
         s.id                AS schedule_id,
         p.amount            AS amount
  FROM payments p
  JOIN loan_schedules s ON s.id = p.loan_schedule_id
  LEFT JOIN collection_assignments ca ON ca.id = p.collection_assignment_id
  WHERE p.status = 'verified'
    AND (ca.status IS NULL OR ca.status NOT IN ('pending_approval', 'rejected'))

  UNION

  -- (b) payment → collection_assignment → loan_schedule (fallback)
  SELECT DISTINCT
         p.id,
         s.loan_id,
         s.id,
         p.amount
  FROM payments p
  JOIN collection_assignments ca ON ca.id = p.collection_assignment_id
  JOIN loan_schedules s ON s.id = ca.loan_schedule_id
  WHERE p.status = 'verified'
    AND ca.status NOT IN ('pending_approval', 'rejected')
),
sched AS (
  SELECT s.loan_id,
         s.amount_due,
         s.due_date,
         -- Isang bayad, isang beses lang mabibilang sa bawat schedule.
         COALESCE((
           SELECT SUM(x.amount)
           FROM (SELECT DISTINCT e.payment_id, e.amount
                 FROM effective e
                 WHERE e.schedule_id = s.id) x
         ), 0) AS amount_paid
  FROM loan_schedules s
),
unpaid_overdue AS (
  SELECT DISTINCT loan_id
  FROM sched
  WHERE amount_paid < amount_due
    AND due_date < (now_manila())::date
),
paid_total AS (
  -- Dedupe ayon sa payment id (kapareho ng sumVerifiedPaymentsByLoan).
  SELECT loan_id, SUM(amount) AS total
  FROM (SELECT DISTINCT payment_id, loan_id, amount FROM effective) x
  GROUP BY loan_id
),
penalty_total AS (
  SELECT loan_id, SUM(penalty_amount) AS total
  FROM penalty_logs
  GROUP BY loan_id
),
balance AS (
  SELECT l.id,
         GREATEST(
           0,
           ROUND(l.principal_amount * (1 + l.interest_rate / 100.0), 2)
             + COALESCE(pen.total, 0)
             - COALESCE(paid.total, 0)
         ) AS outstanding
  FROM loans l
  LEFT JOIN paid_total paid ON paid.loan_id = l.id
  LEFT JOIN penalty_total pen ON pen.loan_id = l.id
  WHERE l.status = 'overdue'
)
UPDATE loans l
SET status = CASE WHEN b.outstanding <= 0 THEN 'completed' ELSE 'active' END
FROM balance b
WHERE l.id = b.id
  AND NOT EXISTS (
    SELECT 1 FROM unpaid_overdue u WHERE u.loan_id = l.id
  );

COMMIT;
