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
ALTER PUBLICATION supabase_realtime DROP TABLE public.account_upgrade_documents;
ALTER PUBLICATION supabase_realtime ADD TABLE public.account_upgrade_documents;

-- ─────────────────────────────────────────────────────────────────────
-- 6) Storage bucket + policies
-- ─────────────────────────────────────────────────────────────────────
-- storage.objects has an FK (objects_bucketId_fkey) on storage.buckets.id,
-- so we cannot rename the bucket's primary key while files still reference
-- 'kyc-documents'. Order: create the new bucket row, repoint objects, then
-- remove the old bucket row.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types, owner, created_at, updated_at)
SELECT 'account-upgrade-documents', 'account-upgrade-documents', public,
       file_size_limit, allowed_mime_types, owner, created_at, updated_at
FROM storage.buckets
WHERE id = 'kyc-documents'
  AND NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'account-upgrade-documents');

UPDATE storage.objects
SET bucket_id = 'account-upgrade-documents'
WHERE bucket_id = 'kyc-documents';

-- NOTE: the now-empty 'kyc-documents' bucket is intentionally left in place.
-- Postgres blocks direct DELETE from storage tables ("use the Storage API"),
-- so it is removed via the Storage Admin API (storage/v1/bucket/kyc-documents)
-- after this migration is applied.

-- Policies are DROPPED and re-created (not just renamed): ALTER POLICY
-- RENAME would leave the policy body reading `bucket_id = 'kyc-documents'`,
-- which no longer exists after the bucket rename above.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND (policyname IN ('kyc_docs_own_read','kyc_docs_own_upload',
                          'kyc_docs_own_update','kyc_docs_own_delete')
           OR policyname IN ('account_upgrade_docs_own_read','account_upgrade_docs_own_upload',
                             'account_upgrade_docs_own_update','account_upgrade_docs_own_delete'))
  ) THEN
    DROP POLICY IF EXISTS "kyc_docs_own_read"    ON storage.objects;
    DROP POLICY IF EXISTS "kyc_docs_own_upload"  ON storage.objects;
    DROP POLICY IF EXISTS "kyc_docs_own_update"  ON storage.objects;
    DROP POLICY IF EXISTS "kyc_docs_own_delete"  ON storage.objects;
    DROP POLICY IF EXISTS "account_upgrade_docs_own_read"    ON storage.objects;
    DROP POLICY IF EXISTS "account_upgrade_docs_own_upload"  ON storage.objects;
    DROP POLICY IF EXISTS "account_upgrade_docs_own_update"  ON storage.objects;
    DROP POLICY IF EXISTS "account_upgrade_docs_own_delete"  ON storage.objects;
  END IF;
END $$;

CREATE POLICY "account_upgrade_docs_own_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'account-upgrade-documents' AND owner = auth.uid());

CREATE POLICY "account_upgrade_docs_own_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'account-upgrade-documents' AND owner = auth.uid());

CREATE POLICY "account_upgrade_docs_own_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'account-upgrade-documents' AND owner = auth.uid())
  WITH CHECK (bucket_id = 'account-upgrade-documents' AND owner = auth.uid());

CREATE POLICY "account_upgrade_docs_own_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'account-upgrade-documents' AND owner = auth.uid());

-- ─────────────────────────────────────────────────────────────────────
-- 7) Enum/status VALUES that carried a kyc_ prefix
-- ─────────────────────────────────────────────────────────────────────
-- loan_statuses: kyc_required → account_upgrade_required
UPDATE loan_statuses SET code = 'account_upgrade_required', label = 'Account Upgrade Required'
WHERE code = 'kyc_required';

-- notification_types: kyc_* → account_upgrade_*
-- notifications.type FKs notification_types.code and existing rows still use
-- the old codes, so drop the FK, rename codes + rows, then re-add the FK.
ALTER TABLE notifications DROP CONSTRAINT notifications_type_fkey;

UPDATE notification_types SET code = 'account_upgrade_required',  label = 'Account Upgrade Required'
WHERE code = 'kyc_required';
UPDATE notification_types SET code = 'account_upgrade_submitted', label = 'Account Upgrade Submitted'
WHERE code = 'kyc_submitted';
UPDATE notification_types SET code = 'account_upgrade_update',   label = 'Account Upgrade Update'
WHERE code = 'kyc_update';

UPDATE notifications SET type = 'account_upgrade_required'  WHERE type = 'kyc_required';
UPDATE notifications SET type = 'account_upgrade_submitted' WHERE type = 'kyc_submitted';
UPDATE notifications SET type = 'account_upgrade_update'    WHERE type = 'kyc_update';

ALTER TABLE notifications ADD CONSTRAINT notifications_type_fkey
  FOREIGN KEY (type) REFERENCES notification_types(code);

COMMIT;
