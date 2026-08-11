-- ═══════════════════════════════════════════════════════════════════════════
-- Jireta Loans & Credit Corp 1966
-- Migration : 00034_remove_blacklist_and_suspend.sql
-- Purpose   : Remove the blacklist feature and the 'suspended' account status.
--
--   • blacklist table is dropped entirely (its RLS policies, indexes and
--     foreign keys are dropped with the table).
--   • 'suspended' is removed from user_account_statuses; any existing
--     suspended accounts are downgraded to 'inactive' first.
--   • fn_otp_guard_account_status no longer references 'suspended'.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Blacklist
--    (DROP TABLE removes the table from supabase_realtime automatically.)
-- ─────────────────────────────────────────────────────────────────────────────

DROP TABLE IF EXISTS public.blacklist;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) 'suspended' account status
-- ─────────────────────────────────────────────────────────────────────────────

-- Existing suspended accounts keep a valid status: move them to inactive.
UPDATE public.users
SET    account_status = 'inactive',
       updated_at     = NOW()
WHERE  account_status = 'suspended';

DELETE FROM public.user_account_statuses WHERE code = 'suspended';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) OTP guard trigger — no 'suspended' status anymore.
-- ─────────────────────────────────────────────────────────────────────────────

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

  IF v_status IN ('archived', 'inactive') THEN
    RAISE EXCEPTION 'Cannot send OTP — account is %', v_status
      USING ERRCODE = 'P0002';
  END IF;

  RETURN NEW;
END;
$$;

COMMIT;
