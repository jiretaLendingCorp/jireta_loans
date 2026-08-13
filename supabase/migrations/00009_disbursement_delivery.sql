-- Migration : 00009_disbursement_delivery.sql
-- Purpose   : Rider cash-delivery disbursement support.
--             1) add delivered_at to disbursements (set when the rider hands
--                the cash to the lender and uploads proof),
--             2) create the private 'disbursement-proofs' storage bucket used
--                by the disbursements-delivery ?fn=upload-proof edge function.

-- 1) disbursements.delivered_at
ALTER TABLE disbursements
  ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;

-- 2) storage bucket for cash-delivery proof photos
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('disbursement-proofs', 'disbursement-proofs', FALSE, 10485760,
        ARRAY['image/png','image/jpeg','image/webp']::text[])
ON CONFLICT (id) DO NOTHING;

-- 3) storage policies — riders upload proof; staff / lenders may read it
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'disbursement_proofs_rider_upload'
  ) THEN
    CREATE POLICY "disbursement_proofs_rider_upload" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (
        bucket_id = 'disbursement-proofs'
        AND (
          auth.role() IN ('head_manager','employee')
          OR EXISTS (
            SELECT 1 FROM users
            WHERE users.id = auth.uid()
              AND users.account_status = 'active'
          )
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'disbursement_proofs_authenticated_read'
  ) THEN
    CREATE POLICY "disbursement_proofs_authenticated_read" ON storage.objects
      FOR SELECT TO authenticated
      USING (bucket_id = 'disbursement-proofs');
  END IF;
END $$;
