-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00144_backfill_walkin_frequency.sql
-- Purpose   : Walk-in applications created before the wizard started
--             persisting the borrower's chosen payment frequency left
--             application_loan_details.payment_frequency NULL. When such
--             an application is converted to a loan (in-office-view submit
--             or the KYC auto-convert path) the edge function defaults the
--             frequency to 'monthly' — which is why staff kept seeing
--             "Loan Term: X months" for loans that were actually applied
--             daily or weekly.
--
--             Fix: backfill application_loan_details.payment_frequency from
--             the already-converted loan (loans.in_office_application_id),
--             which always carries the correct code. Also repair any loan
--             whose varchar payment_frequency drifted out of sync with its
--             canonical payment_frequency_id (the two are trigger-synced,
--             but legacy rows written before 00110 may disagree).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- 1) Walk-in applications already converted to a loan: copy the loan's
--    frequency onto the application's loan details so any future re-submit /
--    edit / view shows the borrower's real choice.
UPDATE application_loan_details ald
SET payment_frequency = l.payment_frequency,
    updated_at        = now_manila()
FROM loans l
WHERE l.in_office_application_id = ald.application_id
  AND ald.payment_frequency IS NULL
  AND l.payment_frequency IS NOT NULL;

-- 2) Loans whose varchar payment_frequency disagrees with the canonical
--    lookup join get re-synced (safety net — normally the trigger handles
--    this on write).
UPDATE loans l
SET payment_frequency = pf.code
FROM payment_frequencies pf
WHERE pf.id = l.payment_frequency_id
  AND l.payment_frequency IS DISTINCT FROM pf.code;

COMMIT;