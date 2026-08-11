-- /supabase/migrations/00033_fix_google_lender_email.sql
-- Google OAuth lenders are identified by email, but migration 00020's
-- fn_users_rider_lender_no_email trigger nulled the email on EVERY rider/lender
-- insert. The Google self-registration insert (email present, phone null) then
-- violated the users_email_or_phone CHECK and failed with
-- "Failed to create account".
--
-- Fix: keep real emails (Google sign-in lenders). Only strip the synthetic temp
-- credential (`%@jireta.temp`) used internally by the phone-OTP flow, so
-- phone-identified lenders/riders stay email-free.

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_users_rider_lender_no_email()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $fn$
DECLARE
  v_role VARCHAR(50);
BEGIN
  SELECT name INTO v_role FROM roles WHERE id = NEW.role_id;
  IF v_role IN ('rider', 'lender') THEN
    -- A real email identifies a Google sign-in lender and must be kept. Only
    -- synthetic OTP temp emails and empty values are stripped.
    IF NEW.email IS NULL OR NEW.email ILIKE '%@jireta.temp' THEN
      NEW.email := NULL;
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

COMMIT;
