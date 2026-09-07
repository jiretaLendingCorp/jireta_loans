-- =====================================================================
-- Migration: 00137_mirror_walkin_docs_trigger.sql
-- Purpose  : DB-level guarantee that a submitted walk-in application's
--            documents are visible on EVERY Account Upgrade surface.
--
--            Walk-in files are uploaded to application_documents (loan-
--            documents bucket) but the Account Upgrade screens read
--            account_upgrade_documents. Migration 00133/00136 backfill
--            rows created before them, and the edge function mirrors docs
--            at submit time — but that still depends on the in-office-view
--            function being deployed. This trigger moves the mirroring
--            into the database: the moment an in_office_applications row
--            becomes 'submitted'/'converted' (with a lender linked), every
--            application document is copied into account_upgrade_documents
--            as 'verified' (staff checked the originals in person). No
--            code path — current or future — can leave a submitted walk-in
--            showing "No documents submitted."
--
-- Safe / idempotent:
--   • Only fires for submitted/converted rows with lender_id set.
--   • NOT EXISTS guard per (lender_id, document_type) — retries, the
--     edge-function mirror and the 00133/00136 backfills never duplicate.
--   • file_size uses the 1-byte placeholder (application_documents has no
--     file_size column); display only, files open via file_path.
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION mirror_walkin_docs_to_account_upgrade()
RETURNS trigger AS $$
BEGIN
  IF NEW.lender_id IS NULL OR NEW.status NOT IN ('submitted', 'converted') THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.account_upgrade_documents
    (lender_id, document_type, file_path, file_name, file_size, mime_type,
     status, reviewed_by, reviewed_at, uploaded_at)
  SELECT
    NEW.lender_id,
    ad.document_type,
    ad.file_path,
    ad.file_name,
    1, -- placeholder (in-office rows do not track file_size)
    COALESCE(ad.mime_type, 'application/octet-stream'),
    'verified',
    NEW.created_by,
    NOW(),
    COALESCE(ad.uploaded_at, NOW())
  FROM public.application_documents ad
  WHERE ad.application_id = NEW.id
    AND ad.file_path IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.account_upgrade_documents aud
      WHERE aud.lender_id = NEW.lender_id
        AND aud.document_type = ad.document_type
    );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_mirror_walkin_docs_to_upgrade ON public.in_office_applications;
CREATE TRIGGER trg_mirror_walkin_docs_to_upgrade
AFTER INSERT OR UPDATE OF status, lender_id ON public.in_office_applications
FOR EACH ROW
EXECUTE FUNCTION mirror_walkin_docs_to_account_upgrade();

COMMIT;
