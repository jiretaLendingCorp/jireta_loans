-- =====================================================================
-- Jireta Loans & Credit Corp
-- Migration : 00192_email_change_otp.sql
-- Purpose   :
--   Payagan ang `purpose = 'email_change'` sa `otp_codes` — ang 6-digit na
--   code na ipinapadala sa BAGONG email ng rider / lender bago maisulat ang
--   pagbabago (`users-manage?fn=request-email-change` at
--   `?fn=confirm-email-change`).
--
--   Hiwalay ang purpose na ito sa `login` at `reset_mpin` para hindi
--   magamit ang isang code sa ibang flow (tingnan ang `otpRejectionReason`).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

ALTER TABLE public.otp_codes
  DROP CONSTRAINT IF EXISTS chk_otp_codes_purpose;

ALTER TABLE public.otp_codes
  ADD CONSTRAINT chk_otp_codes_purpose
  CHECK (purpose IN ('login', 'reset_mpin', 'email_change'));

COMMENT ON COLUMN public.otp_codes.purpose IS
  'Para saan ang OTP: login (pagpasok), reset_mpin (pag-reset ng MPIN), o email_change (pagpapatunay ng bagong email ng rider/lender).';

COMMIT;
