-- /supabase/migrations/00029_approve_without_ci.sql
-- 1) Align loan status vocabulary with application code. The app (and the
--    status-flow trigger) uses `ci_required`, but the loan_statuses reference
--    table only carries the original schema value `kyc_required`. Add the app's
--    spelling and migrate any historical rows so approvals/assignments that
--    reference `ci_required` pass the loans.status FK.
-- 2) Re-apply the relaxed status-flow trigger (idempotent): `approved` may now
--    come directly from pending / under_review / ci_required / ci_assigned /
--    ci_completed, so HM/Employee can approve a loan without a completed CI.

BEGIN;

INSERT INTO loan_statuses (code, label, sort_order, description)
VALUES ('ci_required', 'CI Required', 12, 'Loan flagged for a credit investigation before approval')
ON CONFLICT (code) DO NOTHING;

UPDATE loans SET status = 'ci_required' WHERE status = 'kyc_required';

CREATE OR REPLACE FUNCTION enforce_loan_status_flow()
RETURNS trigger AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status NOT IN ('pending', 'under_review', 'ci_required', 'ci_assigned', 'ci_completed') THEN
    RAISE EXCEPTION 'Loan cannot be approved from % status (was %)', NEW.status, OLD.status;
  END IF;
  IF NEW.status = 'active' AND OLD.status NOT IN ('approved', 'active', 'completed', 'overdue') THEN
    RAISE EXCEPTION 'Loan must be approved before becoming active (was %)', OLD.status;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_loan_status_flow ON loans;
CREATE TRIGGER trg_loan_status_flow
BEFORE UPDATE ON loans
FOR EACH ROW
WHEN (NEW.status IS DISTINCT FROM OLD.status)
EXECUTE FUNCTION enforce_loan_status_flow();

COMMIT;