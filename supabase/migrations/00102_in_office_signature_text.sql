-- 00102_in_office_signature_text.sql
-- borrower_signature stores lender's signature. The Flutter SignaturePad
-- exports a base64-encoded PNG (10-30KB) but the column was VARCHAR(255),
-- so every step-5 save failed with "value too long for type character
-- varying(255)" (22001) and surfaced as PATCH 500 on
-- in-office-create?fn=save-step (see 2026-08-22 16:09 UTC log).
-- Client fix uploads the PNG to storage and stores a short path instead,
-- but widen to TEXT so legacy base64 rows and any future URL forms fit.

ALTER TABLE public.in_office_applications
  ALTER COLUMN borrower_signature TYPE TEXT;
