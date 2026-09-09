-- 00147: Lender Signature (Account Upgrade) + Co-maker Valid ID document.
--
-- 1) The Account Upgrade flow now captures the lender's signature on the
--    Residence Address step. It is uploaded like any other Account Upgrade
--    document (account_upgrade_documents) so head manager / employee
--    reviewers see it after submission — this just registers the type.
--
-- 2) The Apply Loan flow now requires the co-maker's Valid ID alongside
--    their signature. The image is uploaded to a dedicated private bucket
--    and linked via co_maker_documents; staff reviewers resolve signed
--    URLs server-side (loans-view), so no public access is needed.

-- 1) Document type for the lender's Account Upgrade signature.
INSERT INTO document_types (code, label, sort_order)
VALUES ('lender_signature', 'Lender Signature', 17)
ON CONFLICT (code) DO NOTHING;

-- 2) Private storage bucket for co-maker documents (valid ID, etc.).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('co-maker-documents', 'co-maker-documents', FALSE, 10485760,
        ARRAY['image/png','image/jpeg','image/webp','application/pdf']::text[])
ON CONFLICT (id) DO NOTHING;

-- 3) Owner-scoped storage policies (mirror ci-documents) so the uploader's
--    own session can read/upload in the bucket. Staff reviewers never touch
--    the bucket directly — loans-view signs URLs with the service role.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'co_maker_docs_own_read'
  ) THEN
    CREATE POLICY "co_maker_docs_own_read" ON storage.objects
      FOR SELECT TO authenticated
      USING (bucket_id = 'co-maker-documents' AND owner = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'co_maker_docs_own_upload'
  ) THEN
    CREATE POLICY "co_maker_docs_own_upload" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'co-maker-documents' AND owner = auth.uid());
  END IF;
END $$;