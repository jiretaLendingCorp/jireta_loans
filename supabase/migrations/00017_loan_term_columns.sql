-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00017_loan_term_columns.sql
-- Purpose   : Persist the borrower-chosen repayment term on the loan so
--             head manager / employee can see exactly how long the term is
--             and how many installments the borrower chose to pay.
--             loans.term_periods          = number of installments chosen
--             loans.installment_amount    = per-installment amount at apply
--             application_loan_details.term_periods = chosen term in the
--             in-office walk-in wizard (step 3).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

ALTER TABLE loans
  ADD COLUMN IF NOT EXISTS term_periods INT CHECK (term_periods > 0),
  ADD COLUMN IF NOT EXISTS installment_amount DECIMAL(12,2) CHECK (installment_amount > 0);

ALTER TABLE application_loan_details
  ADD COLUMN IF NOT EXISTS term_periods INT CHECK (term_periods > 0);

-- Backfill existing loans from their generated schedule so historical rows
-- also expose the chosen number of payments and the base installment amount.
-- The first schedule row carries the base (non-rounding-adjusted) installment.
UPDATE loans l
SET term_periods      = s.cnt,
    installment_amount = s.first_amount
FROM (
  SELECT ls.loan_id,
         COUNT(*)                                            AS cnt,
         (ARRAY_AGG(ls.amount_due ORDER BY ls.installment_number))[1] AS first_amount
  FROM loan_schedules ls
  GROUP BY ls.loan_id
) s
WHERE l.id = s.loan_id;

-- Backfill in-office applications that already have a schedule stored on
-- their converted loan (term_periods mirrors the loan's schedule count).
UPDATE application_loan_details ald
SET term_periods = l.term_periods
FROM loans l
WHERE l.in_office_application_id = ald.application_id
  AND l.term_periods IS NOT NULL;

COMMIT;