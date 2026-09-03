-- =====================================================================
-- Migration: 00124_account_upgrade_new_doc_types.sql
-- Purpose  : Account Upgrade submit was 400-ing with
--            "Invalid document_type: valid_id_back / mayors_permit /
--             birth_certificate" because the Flutter submit screen sends
--            5 docs (valid_id front, valid_id_back, selfie, mayors_permit,
--            birth_certificate) but document_types + kyc-submit ALLOWED_TYPES
--            only knew the old KYC codes. Also adds employment_types 'other'
--            so free-text "Other" employment never FK-fails the profile update.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- New document types used by the Account Upgrade submit screen.
INSERT INTO document_types (code, label, sort_order)
SELECT v.code, v.label, v.sort_order
FROM (VALUES
  ('valid_id_back',   'Valid ID (Back)',   17),
  ('mayors_permit',   'Mayor''s Permit',    18),
  ('birth_certificate','Birth Certificate', 19)
) AS v(code, label, sort_order)
WHERE NOT EXISTS (
  SELECT 1 FROM document_types d WHERE d.code = v.code
);

-- 'other' employment so custom free-text never violates the FK.
INSERT INTO employment_types (code, label, sort_order)
SELECT 'other', 'Other', 8
WHERE NOT EXISTS (
  SELECT 1 FROM employment_types WHERE code = 'other'
);

COMMIT;
