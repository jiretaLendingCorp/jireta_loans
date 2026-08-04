-- supabase/migrations/00010_loans_lender_fk_cascade.sql
-- Deleting a user cascades into lender_profiles (lender_profiles.id -> users.id
-- ON DELETE CASCADE). loans.lender_id references lender_profiles without any
-- ON DELETE action, so removing a lender/user fails with a
-- 'loans_lender_id_fkey' violation.
--
-- lender_id is NOT NULL, so SET NULL is not an option; CASCADE is used.
-- Loans are also referenced (without ON DELETE) by several downstream tables,
-- so those relations must cascade too for a full user/lender deletion to
-- actually succeed. All the loan-owned children get ON DELETE CASCADE so the
-- entire loan record graph is removed together with its lender.

-- 1) loans -> lender_profiles
ALTER TABLE loans
  DROP CONSTRAINT loans_lender_id_fkey;
ALTER TABLE loans
  ADD CONSTRAINT loans_lender_id_fkey
    FOREIGN KEY (lender_id) REFERENCES lender_profiles(id) ON DELETE CASCADE;

-- 2) Downstream references to loans are cascaded so the delete does not fail
--    partway through the chain.
ALTER TABLE credit_investigations
  DROP CONSTRAINT credit_investigations_loan_id_fkey;
ALTER TABLE credit_investigations
  ADD CONSTRAINT credit_investigations_loan_id_fkey
    FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE;

ALTER TABLE collection_assignments
  DROP CONSTRAINT collection_assignments_loan_id_fkey;
ALTER TABLE collection_assignments
  ADD CONSTRAINT collection_assignments_loan_id_fkey
    FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE;

ALTER TABLE disbursements
  DROP CONSTRAINT disbursements_loan_id_fkey;
ALTER TABLE disbursements
  ADD CONSTRAINT disbursements_loan_id_fkey
    FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE;

ALTER TABLE payments
  DROP CONSTRAINT payments_loan_id_fkey;
ALTER TABLE payments
  ADD CONSTRAINT payments_loan_id_fkey
    FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE;

ALTER TABLE penalty_logs
  DROP CONSTRAINT penalty_logs_loan_id_fkey;
ALTER TABLE penalty_logs
  ADD CONSTRAINT penalty_logs_loan_id_fkey
    FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE;

ALTER TABLE in_office_applications
  DROP CONSTRAINT in_office_applications_loan_id_fkey;
ALTER TABLE in_office_applications
  ADD CONSTRAINT in_office_applications_loan_id_fkey
    FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE;

ALTER TABLE xendit_logs
  DROP CONSTRAINT xendit_logs_loan_id_fkey;
ALTER TABLE xendit_logs
  ADD CONSTRAINT xendit_logs_loan_id_fkey
    FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE;