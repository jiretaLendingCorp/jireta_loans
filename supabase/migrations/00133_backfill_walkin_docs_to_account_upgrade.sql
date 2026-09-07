-- =====================================================================
-- Migration: 00133_backfill_walkin_docs_to_account_upgrade.sql
-- Purpose  : Walk-in (in-office) lenders upload their documents at the
--            office; those live in application_documents (NOT
--            account_upgrade_documents), so the Lender Account Upgrade
--            details screen showed "No documents submitted." for walk-in
--            lenders even though the application was submitted and the
--            account verified. This backfills the collected documents into
--            account_upgrade_documents (status 'verified' — staff checked
--            them in person) so the KYC details/list show them.
--
-- NOTE: application_documents has no file_size column; the CHECK
--       (file_size > 0) is satisfied with a 1-byte placeholder. Only used
--       for display; the details screen opens documents via file_path.
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
  AND ad.file_path IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.account_upgrade_documents aud
    WHERE aud.lender_id = ioa.lender_id
      AND aud.document_type = ad.document_type
  );

COMMIT;