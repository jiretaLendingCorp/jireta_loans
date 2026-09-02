-- supabase/migrations/00030_otp_code_hash.sql
--
-- Widen otp_codes.code so it can store the salted SHA-256 hash of the OTP
-- (64 hex chars) instead of the 6-digit plaintext. The column previously was
-- VARCHAR(6) which could only hold the plaintext code.
--
-- Idempotent: skip if column 'code' doesn't exist (already migrated to otp_hash).

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'otp_codes'
      AND column_name  = 'code'
  ) THEN
    ALTER TABLE public.otp_codes ALTER COLUMN code TYPE TEXT;
    RAISE NOTICE '00030: widened otp_codes.code to TEXT';
  ELSE
    RAISE NOTICE '00030: otp_codes.code does not exist – skipping';
  END IF;
END
$$;
