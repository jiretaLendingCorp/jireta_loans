-- /supabase/migrations/00032_fix_loan_status_flow.sql
-- 1) Close the INSERT loophole. enforce_loan_status_flow() previously ran only
--    on UPDATE, so any direct INSERT (or a future function) could create a loan
--    already in 'approved' / 'active' / 'completed' / 'overdue' without ever
--    going through an approval. Loans must always start as a pre-approval
--    status; they become 'approved' through loans-approve and 'active' only
--    after a disbursement.
-- 2) Repair bad data: an 'active' loan that has no disbursement record was
--    activated out of order. Revert it to 'approved' until funds are actually
--    released, so no loan reads as Active before it was approved.

BEGIN;

CREATE OR REPLACE FUNCTION enforce_loan_status_flow()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status IN ('approved', 'active', 'completed', 'overdue') THEN
      RAISE EXCEPTION 'Loan must be created as a pre-approval status (got %)', NEW.status;
    END IF;
    RETURN NEW;
  END IF;

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
BEFORE INSERT OR UPDATE ON loans
FOR EACH ROW
EXECUTE FUNCTION enforce_loan_status_flow();

-- Revert any 'active' loan that was never actually disbursed back to 'approved'.
UPDATE loans
SET status = 'approved'
WHERE status = 'active'
  AND NOT EXISTS (
    SELECT 1 FROM disbursements d WHERE d.loan_id = loans.id
  );

COMMIT;