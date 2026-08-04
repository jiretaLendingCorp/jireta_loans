-- ═══════════════════════════════════════════════════════════════════════════
-- Jireta Loans & Credit Corp 1966
-- Migration : 00012_allow_unregistered_otp.sql
-- Purpose   : Allow lenders to self-register via OTP login without being
--             pre-registered by the head manager.
--
-- The BEFORE INSERT trigger fn_otp_guard_account_status previously raised
-- P0001 ("phone not registered") whenever an OTP was requested for a phone
-- that had no row in public.users. That blocked the mobile OTP flow for
-- lenders whose accounts had not yet been created by the head manager.
--
-- Change: unknown phones are now allowed to receive an OTP (lender
-- self-registration). Account-status guards for known users remain intact.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION fn_otp_guard_account_status()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_status VARCHAR(20);
BEGIN
  SELECT account_status
  INTO   v_status
  FROM   users
  WHERE  phone_number = NEW.phone_number
  LIMIT  1;

  -- Unregistered phone: allow OTP so lenders can self-register.
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF v_status IN ('suspended', 'archived', 'inactive') THEN
    RAISE EXCEPTION 'Cannot send OTP — account is %', v_status
      USING ERRCODE = 'P0002';
  END IF;

  RETURN NEW;
END;
$$;

COMMIT;
