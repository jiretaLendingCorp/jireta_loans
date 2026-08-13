-- Migration : 00010_disbursement_proof_text.sql
-- Purpose   : Widen disbursements.delivery_proof / borrower_signature to TEXT.
--             Supabase Storage signed URLs for the rider delivery proof exceed
--             VARCHAR(255), causing the ?fn=upload-proof edge function to fail
--             with "value too long for type character varying(255)".

ALTER TABLE disbursements
  ALTER COLUMN delivery_proof     TYPE TEXT,
  ALTER COLUMN borrower_signature TYPE TEXT;
