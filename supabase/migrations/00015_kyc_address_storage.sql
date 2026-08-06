-- /supabase/migrations/00015_kyc_address_storage.sql
-- 1) Extend lender_profiles with the address / source-of-funds fields the
--    KYC flow collects (fixes the ERD gap: lenders had no residence data).
-- 2) Broaden the employment_type + kyc document-type CHECK constraints to the
--    values the app actually sends.
-- 3) Create the `kyc-documents` storage bucket (referenced by the app but
--    never created) and harden the `avatars` bucket policies.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) lender_profiles ERD additions
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE lender_profiles
  ADD COLUMN IF NOT EXISTS street_address TEXT,
  ADD COLUMN IF NOT EXISTS barangay      VARCHAR(100),
  ADD COLUMN IF NOT EXISTS city          VARCHAR(100),
  ADD COLUMN IF NOT EXISTS province      VARCHAR(100),
  ADD COLUMN IF NOT EXISTS zip_code      VARCHAR(10),
  ADD COLUMN IF NOT EXISTS source_of_funds VARCHAR(50);

-- Broaden employment_type to match the app's dropdown options
ALTER TABLE lender_profiles
  DROP CONSTRAINT IF EXISTS lender_profiles_employment_type_check;

ALTER TABLE lender_profiles
  ADD CONSTRAINT lender_profiles_employment_type_check
  CHECK (employment_type IN (
    'employed','self_employed','unemployed','student',
    'business_owner','ofw','freelancer'
  ));

-- One emergency contact per lender (the KYC flow upserts by lender_id)
CREATE UNIQUE INDEX IF NOT EXISTS idx_emergency_lender_id_unique
  ON emergency_contacts(lender_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) kyc_documents: accept the extra document types the KYC/upload flow sends
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE kyc_documents
  DROP CONSTRAINT IF EXISTS kyc_documents_document_type_check;

ALTER TABLE kyc_documents
  ADD CONSTRAINT kyc_documents_document_type_check
  CHECK (document_type IN (
    'valid_id','proof_of_income','barangay_clearance','pay_slip','selfie',
    'proof_of_billing','certificate_of_employment','itr','business_registration',
    'co_maker','other'
  ));

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Storage buckets + policies
-- ─────────────────────────────────────────────────────────────────────────────
-- avatars bucket (public) — idempotent
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('avatars', 'avatars', TRUE, 5242880, ARRAY['image/png','image/jpeg','image/webp']::text[])
ON CONFLICT (id) DO NOTHING;

-- kyc-documents bucket (private; owner reads/writes, staff use service role)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('kyc-documents', 'kyc-documents', FALSE, 10485760,
        ARRAY['image/png','image/jpeg','image/webp','application/pdf']::text[])
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  -- avatars: public read + authenticated upload
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'avatars_public_read'
  ) THEN
    CREATE POLICY "avatars_public_read" ON storage.objects
      FOR SELECT USING (bucket_id = 'avatars');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'avatars_auth_upload'
  ) THEN
    CREATE POLICY "avatars_auth_upload" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'avatars');
  END IF;

  -- kyc-documents: owner-scoped access so users can only touch their own files
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'kyc_docs_own_read'
  ) THEN
    CREATE POLICY "kyc_docs_own_read" ON storage.objects
      FOR SELECT TO authenticated
      USING (bucket_id = 'kyc-documents' AND owner = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'kyc_docs_own_upload'
  ) THEN
    CREATE POLICY "kyc_docs_own_upload" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'kyc-documents' AND owner = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'kyc_docs_own_update'
  ) THEN
    CREATE POLICY "kyc_docs_own_update" ON storage.objects
      FOR UPDATE TO authenticated
      USING (bucket_id = 'kyc-documents' AND owner = auth.uid())
      WITH CHECK (bucket_id = 'kyc-documents' AND owner = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'kyc_docs_own_delete'
  ) THEN
    CREATE POLICY "kyc_docs_own_delete" ON storage.objects
      FOR DELETE TO authenticated
      USING (bucket_id = 'kyc-documents' AND owner = auth.uid());
  END IF;
END $$;

COMMIT;
