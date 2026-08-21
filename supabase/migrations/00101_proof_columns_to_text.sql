-- 00101_proof_columns_to_text.sql
-- Proof storage columns must hold storage paths / signed URLs. Signed URLs
-- embed a JWT token and routinely exceed 255 characters, which made every
-- collection-completion UPDATE fail with "value too long" — leaving
-- assignments stuck in 'in_progress' while riders were told the upload
-- succeeded. Widen to TEXT so any URL form fits.

ALTER TABLE collection_assignments ALTER COLUMN proof_photo        TYPE TEXT;
ALTER TABLE collection_assignments ALTER COLUMN borrower_signature TYPE TEXT;
ALTER TABLE collection_assignments ALTER COLUMN collection_photo   TYPE TEXT;
