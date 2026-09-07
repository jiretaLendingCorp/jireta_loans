-- =====================================================================
-- Migration: 00136_backfill_new_walkin_docs_to_account_upgrade.sql
-- Purpose  : Migration 00133 mirrored walk-in (application_documents)
--            uploads into account_upgrade_documents ONCE at that point in
--            time. Every walk-in application submitted AFTER 00133 has its
--            documents in application_documents only, so the Account
--            Upgrade surfaces that read account_upgrade_documents (details /
--            status / the lender's own Documents page) showed
--            "No documents submitted." for those lenders even though the
--            office collected + checked the files in person.
--
--            New submissions are now mirrored by the edge function
--            (in-office-view submit-account / submit); this backfill repairs
--            walk-ins submitted between 00133 and that code deploy.
--
-- NOTE: application_documents has no file_size column; the CHECK
--       (file_size > 0) is satisfied with a 1-byte placeholder (display
--       only — files open via file_path against the loan-documents bucket).
-- Idempotent: skips (lender_id, document_type) pairs already present.
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

INSERT INTO public.account_upgrade_documents
  (lender_id, document_type, file_path, file_name, file_size, mime_type,
   status, reviewed_by, reviewed_at, uploaded_at)
SELECT
  ioa.lender_id,
  ad.document_type,
  ad.file_path,
  ad.file_name,
  1, -- placeholder (in-office rows do not track file_size)
  COALESCE(ad.mime_type, 'application/octet-stream'),
  'verified',
  ioa.created_by,
  NOW(),
  COALESCE(ad.uploaded_at, NOW())
FROM public.application_documents ad
JOIN public.in_office_applications ioa ON ioa.id = ad.application_id
WHERE ioa.lender_id IS NOT NULL
  AND ioa.status IN ('submitted', 'converted')
  AND ad.file_path IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.account_upgrade_documents aud
    WHERE aud.lender_id = ioa.lender_id
      AND aud.document_type = ad.document_type
  );

COMMIT;
