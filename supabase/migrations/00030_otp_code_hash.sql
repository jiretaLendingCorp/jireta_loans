-- supabase/migrations/00030_otp_code_hash.sql
--
-- Widen otp_codes.code so it can store the salted SHA-256 hash of the OTP
-- (64 hex chars) instead of the 6-digit plaintext. The column previously was
-- VARCHAR(6) which could only hold the plaintext code.

ALTER TABLE public.otp_codes
  ALTER COLUMN code TYPE TEXT;