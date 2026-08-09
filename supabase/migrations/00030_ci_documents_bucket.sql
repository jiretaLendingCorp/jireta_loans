-- /supabase/migrations/00030_ci_documents_bucket.sql
-- Storage bucket for rider-uploaded credit-investigation photos. All writes and
-- reads flow through edge functions using the service role (which bypasses RLS),
-- so the policies below are belt-and-braces owner-scoped access for the rider.
-- Mirrors the existing kyc-documents bucket setup in 00015.

BEGIN;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('ci-documents', 'ci-documents', FALSE, 10485760,
        ARRAY['image/png','image/jpeg','image/webp','application/pdf']::text[])
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'ci_docs_own_read'
  ) THEN
    CREATE POLICY "ci_docs_own_read" ON storage.objects
      FOR SELECT TO authenticated
      USING (bucket_id = 'ci-documents' AND owner = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'ci_docs_own_upload'
  ) THEN
    CREATE POLICY "ci_docs_own_upload" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'ci-documents' AND owner = auth.uid());
  END IF;
END $$;

COMMIT;