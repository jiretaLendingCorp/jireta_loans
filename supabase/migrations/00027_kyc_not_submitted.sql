-- /supabase/migrations/00027_kyc_not_submitted.sql
-- New lenders have not completed KYC yet. Store that as an explicit
-- `not_submitted` state instead of `pending`, which the app rendered as
-- "Under Review" the moment the account was created.
--
-- `pending` remains a valid document-level status (a submitted doc is pending
-- review); only the profile-level initial state changes here.

BEGIN;

INSERT INTO kyc_statuses (code, label, description, sort_order) VALUES
  ('not_submitted', 'Not Submitted', 'Lender has not submitted KYC documents yet', 0)
ON CONFLICT (code) DO NOTHING;

ALTER TABLE lender_profiles
  ALTER COLUMN kyc_status SET DEFAULT 'not_submitted';

-- Any lender still at `pending` never completed a submission (kyc-submit flips
-- to `submitted`), so the pending rows are all not-yet-submitted accounts.
UPDATE lender_profiles
SET kyc_status = 'not_submitted'
WHERE kyc_status = 'pending';

COMMIT;
