-- Migration : 00025_in_office_documents_storage.sql
-- Purpose   : Storage bucket for walk-in / in-office application documents.
--             The walk-in wizard uploads Valid ID, Proof of Income, Barangay
--             Clearance and Pay Slip files to this bucket, then stores the
--             object path in application_documents.file_path (later copied to
--             loan_documents.file_path when the application is converted).

-- 1) private 'loan-documents' storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('loan-documents', 'loan-documents', FALSE, 10485760,
        ARRAY['image/png','image/jpeg','image/webp','application/pdf']::text[])
ON CONFLICT (id) DO NOTHING;

-- 2) storage policies — any active user (staff walk-in wizard) may upload;
--    authenticated users may read the documents
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'loan_documents_active_user_upload'
  ) THEN
    CREATE POLICY "loan_documents_active_user_upload" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (
        bucket_id = 'loan-documents'
        AND EXISTS (
          SELECT 1 FROM users
          WHERE users.id = auth.uid()
            AND users.account_status = 'active'
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'loan_documents_authenticated_read'
  ) THEN
    CREATE POLICY "loan_documents_authenticated_read" ON storage.objects
      FOR SELECT TO authenticated
      USING (bucket_id = 'loan-documents');
  END IF;
END $$;
