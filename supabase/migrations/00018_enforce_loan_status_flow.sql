-- 00018_enforce_loan_status_flow.sql
-- Enforce the loan lifecycle at the database level so a loan can never
-- become 'approved' or 'active' out of order, even if a function is bypassed.
--
-- Lifecycle: pending -> ci_assigned -> ci_completed -> approved -> active
--   - approved can only come from ci_completed
--   - active can only come from approved (or be restored from
--     completed/overdue when a payment is reversed)

CREATE OR REPLACE FUNCTION enforce_loan_status_flow()
RETURNS trigger AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status <> 'ci_completed' THEN
    RAISE EXCEPTION 'Loan must be in ci_completed status before approval (was %)', OLD.status;
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
