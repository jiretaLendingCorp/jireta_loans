-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00008_kyc_to_account_upgrade.sql
-- Purpose   : Rename the "KYC" (identity verification) concept to
--             "Account Upgrade". This is a rename-only migration: the
--             status VALUES (not_submitted, pending, submitted,
--             under_review, verified, rejected) are unchanged, and the
--             business logic / data flow is preserved.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) Rename tables
-- ─────────────────────────────────────────────────────────────────────
ALTER TABLE kyc_statuses  RENAME TO account_upgrade_statuses;
ALTER TABLE kyc_documents RENAME TO account_upgrade_documents;

-- ─────────────────────────────────────────────────────────────────────
-- 2) Rename columns / indexes on lender_profiles
-- ─────────────────────────────────────────────────────────────────────
ALTER TABLE lender_profiles RENAME COLUMN kyc_status TO account_upgrade_status;
ALTER TABLE lender_profiles RENAME COLUMN kyc_rejection_notes TO account_upgrade_rejection_notes;

ALTER INDEX idx_lender_kyc_status RENAME TO idx_lender_account_upgrade_status;

-- ─────────────────────────────────────────────────────────────────────
-- 3) Rename indexes on the renamed kyc_documents → account_upgrade_documents
-- ─────────────────────────────────────────────────────────────────────
ALTER INDEX idx_kyc_docs_lender_id RENAME TO idx_account_upgrade_docs_lender_id;
ALTER INDEX idx_kyc_docs_status    RENAME TO idx_account_upgrade_docs_status;

-- ─────────────────────────────────────────────────────────────────────
-- 4) RLS policy rename (now on the renamed table)
-- ─────────────────────────────────────────────────────────────────────
ALTER POLICY kyc_documents_read ON account_upgrade_documents
  RENAME TO account_upgrade_documents_read;

-- ─────────────────────────────────────────────────────────────────────
-- 5) Realtime publication: remove old table, add renamed one
-- ─────────────────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime DROP TABLE public.kyc_documents;
ALTER PUBLICATION supabase_realtime ADD TABLE public.account_upgrade_documents;

-- ─────────────────────────────────────────────────────────────────────
-- 6) Storage bucket + policies
-- ─────────────────────────────────────────────────────────────────────
UPDATE storage.buckets
SET id = 'account-upgrade-documents', name = 'account-upgrade-documents'
WHERE id = 'kyc-documents';

DO $$
DECLARE
  old_policy TEXT;
  new_policy TEXT;
BEGIN
  FOREACH old_policy IN ARRAY ARRAY[
    'kyc_docs_own_read','kyc_docs_own_upload',
    'kyc_docs_own_update','kyc_docs_own_delete'
  ] LOOP
    new_policy := replace(old_policy, 'kyc_docs_own', 'account_upgrade_docs_own');
    EXECUTE format(
      'ALTER POLICY %I ON storage.objects RENAME TO %I;',
      old_policy, new_policy
    );
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 7) Enum/status VALUES that carried a kyc_ prefix
-- ─────────────────────────────────────────────────────────────────────
-- loan_statuses: kyc_required → account_upgrade_required
UPDATE loan_statuses SET code = 'account_upgrade_required', label = 'Account Upgrade Required'
WHERE code = 'kyc_required';

-- notification_types: kyc_* → account_upgrade_*
UPDATE notification_types SET code = 'account_upgrade_required',  label = 'Account Upgrade Required'
WHERE code = 'kyc_required';
UPDATE notification_types SET code = 'account_upgrade_submitted', label = 'Account Upgrade Submitted'
WHERE code = 'kyc_submitted';
UPDATE notification_types SET code = 'account_upgrade_update',   label = 'Account Upgrade Update'
WHERE code = 'kyc_update';

COMMIT;
