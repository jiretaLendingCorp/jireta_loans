-- /supabase/migrations/00014_kyc_co_maker_docs.sql
-- Allow co-maker documents in the KYC documents table (upload screen sends 'co_maker').

BEGIN;

ALTER TABLE kyc_documents
  DROP CONSTRAINT IF EXISTS kyc_documents_document_type_check;

ALTER TABLE kyc_documents
  ADD CONSTRAINT kyc_documents_document_type_check
  CHECK (document_type IN ('valid_id','proof_of_income','barangay_clearance','pay_slip','selfie','proof_of_billing','co_maker','other'));

COMMIT;
