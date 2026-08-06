-- /supabase/migrations/00013_co_maker_signature_avatars.sql
-- Fix ERD: co-makers need a signature (loan applications require a signed co-maker)
-- Create avatars storage bucket + policies for profile pictures.

BEGIN;

-- 1) Co-maker signature
ALTER TABLE co_makers
  ADD COLUMN IF NOT EXISTS signature TEXT;

-- 2) Avatars storage bucket (idempotent)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('avatars', 'avatars', TRUE, 5242880, ARRAY['image/png','image/jpeg','image/webp']::text[])
ON CONFLICT (id) DO NOTHING;

-- 3) Bucket locking automation not required; ensure policies exist idempotently
DO $$
BEGIN
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
END $$;

COMMIT;