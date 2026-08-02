-- ═══════════════════════════════════════════════════════════════════════════
-- Jireta Loans & Credit Corp 1966
-- Migration: 00005_auth_triggers.sql
-- Purpose  : Database-level triggers supporting user registration & login
-- Covers   : Web login (email/password), Mobile login (OTP), password
--             management, account lockout, and audit trail automation
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- TRIGGER 1: Auto-update users.last_login_at on successful login
--
-- Why: Both auth-login and auth-verify-otp Edge Functions call a separate
--      UPDATE after inserting the login_success auth_log. This trigger
--      consolidates that into a single DB-level operation, removing the
--      second round-trip entirely.
--
-- Fires: AFTER INSERT on auth_logs WHERE event_type = 'login_success'
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_auth_update_last_login()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE users
  SET last_login_at = NEW.created_at
  WHERE id = NEW.user_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auth_update_last_login
  AFTER INSERT ON auth_logs
  FOR EACH ROW
  WHEN (NEW.event_type = 'login_success')
  EXECUTE FUNCTION fn_auth_update_last_login();

COMMENT ON FUNCTION fn_auth_update_last_login() IS
  'Propagates login_success event timestamp to users.last_login_at automatically.';


-- ─────────────────────────────────────────────────────────────────────────────
-- TRIGGER 2: Auto-insert account_locked audit event on 5th login failure
--
-- Why: The auth-login Edge Function sets is_locked = TRUE on the 5th failed
--      attempt but only writes a login_fail record. This trigger also inserts
--      a dedicated account_locked entry, giving head_managers a clean event
--      type to filter in the audit log screen.
--
-- Fires: AFTER INSERT on auth_logs WHERE event_type = 'login_fail'
--        AND is_locked = TRUE
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_auth_record_account_locked()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO auth_logs (
    user_id,
    event_type,
    ip_address,
    user_agent,
    failed_attempts,
    is_locked
  )
  VALUES (
    NEW.user_id,
    'account_locked',
    NEW.ip_address,
    NEW.user_agent,
    NEW.failed_attempts,
    TRUE
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auth_record_account_locked
  AFTER INSERT ON auth_logs
  FOR EACH ROW
  WHEN (NEW.event_type = 'login_fail' AND NEW.is_locked = TRUE)
  EXECUTE FUNCTION fn_auth_record_account_locked();

COMMENT ON FUNCTION fn_auth_record_account_locked() IS
  'Auto-inserts an account_locked audit event when the 5th login failure marks the account locked.';


-- ─────────────────────────────────────────────────────────────────────────────
-- TRIGGER 3: Guard OTP creation — reject if account is not active
--
-- Why: auth-send-otp already checks account_status in application code, but
--      the otp_codes table has no FK constraint to enforce this. This BEFORE
--      trigger provides a DB-level safety net so no OTP can ever be inserted
--      for a suspended, inactive, or archived user, even via direct SQL or
--      a bug in the Edge Function.
--
-- Fires: BEFORE INSERT on otp_codes
-- Raises: P0001 (phone not registered) or P0002 (account not active)
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

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Phone number % is not registered to any user', NEW.phone_number
      USING ERRCODE = 'P0001';
  END IF;

  IF v_status IN ('suspended', 'archived', 'inactive') THEN
    RAISE EXCEPTION 'Cannot send OTP — account is %', v_status
      USING ERRCODE = 'P0002';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_otp_guard_account_status
  BEFORE INSERT ON otp_codes
  FOR EACH ROW
  EXECUTE FUNCTION fn_otp_guard_account_status();

COMMENT ON FUNCTION fn_otp_guard_account_status() IS
  'Blocks OTP insertion for suspended, archived, or unregistered phone numbers.';


-- ─────────────────────────────────────────────────────────────────────────────
-- TRIGGER 4: Invalidate all previous active OTPs when a new one is issued
--
-- Why: auth-send-otp runs an explicit UPDATE to mark old OTPs as used before
--      inserting the new one. Because those two operations are not atomic,
--      a race condition could leave two valid OTPs alive briefly. Moving the
--      invalidation to AFTER INSERT on the new row makes it atomic with the
--      insert under the same transaction.
--
-- Fires: AFTER INSERT on otp_codes
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_otp_invalidate_previous()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE otp_codes
  SET    used = TRUE
  WHERE  phone_number = NEW.phone_number
    AND  used         = FALSE
    AND  id          != NEW.id;          -- spare the row we just inserted
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_otp_invalidate_previous
  AFTER INSERT ON otp_codes
  FOR EACH ROW
  EXECUTE FUNCTION fn_otp_invalidate_previous();

COMMENT ON FUNCTION fn_otp_invalidate_previous() IS
  'Atomically invalidates all prior active OTPs for a phone when a new OTP is issued.';


-- ─────────────────────────────────────────────────────────────────────────────
-- TRIGGER 5: Log otp_fail event when an OTP hits the max attempt ceiling
--
-- Why: The auth-verify-otp Edge Function increments otp_codes.attempts on
--      every wrong guess but only marks the row used when the limit is
--      exceeded. It does NOT write an otp_fail event to auth_logs, leaving
--      OTP brute-force attempts invisible to auditors. This trigger fills
--      that gap.
--
-- Fires: AFTER UPDATE OF attempts ON otp_codes
--        WHEN old attempts < 5 AND new attempts >= 5
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_otp_log_max_attempts()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id UUID;
BEGIN
  SELECT id
  INTO   v_user_id
  FROM   users
  WHERE  phone_number = NEW.phone_number
  LIMIT  1;

  IF v_user_id IS NOT NULL THEN
    INSERT INTO auth_logs (
      user_id,
      event_type,
      failed_attempts,
      is_locked
    )
    VALUES (
      v_user_id,
      'otp_fail',
      NEW.attempts,
      FALSE
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_otp_log_max_attempts
  AFTER UPDATE OF attempts ON otp_codes
  FOR EACH ROW
  WHEN (OLD.attempts < 5 AND NEW.attempts >= 5)
  EXECUTE FUNCTION fn_otp_log_max_attempts();

COMMENT ON FUNCTION fn_otp_log_max_attempts() IS
  'Writes an otp_fail audit event when an OTP reaches the 5-attempt lockout threshold.';


-- ─────────────────────────────────────────────────────────────────────────────
-- TRIGGER 6: Log force_password_changed event when first-login password is set
--
-- Why: auth-force-change-password updates users.force_password_change = FALSE
--      and then writes a separate auth_log INSERT. This trigger eliminates the
--      second round-trip: changing the column is now enough to produce the
--      audit record automatically.
--
-- Fires: AFTER UPDATE OF force_password_change ON users
--        WHEN old = TRUE AND new = FALSE
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_users_log_force_password_changed()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO auth_logs (
    user_id,
    event_type,
    failed_attempts,
    is_locked
  )
  VALUES (
    NEW.id,
    'force_password_changed',
    0,
    FALSE
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_log_force_password_changed
  AFTER UPDATE OF force_password_change ON users
  FOR EACH ROW
  WHEN (OLD.force_password_change = TRUE AND NEW.force_password_change = FALSE)
  EXECUTE FUNCTION fn_users_log_force_password_changed();

COMMENT ON FUNCTION fn_users_log_force_password_changed() IS
  'Auto-logs the force_password_changed audit event when a user completes their mandatory first-login password reset.';


-- ─────────────────────────────────────────────────────────────────────────────
-- TRIGGER 7: Maintain rolling password history — keep only the last 5 entries
--
-- Why: auth-force-change-password and auth-reset-password both insert into
--      password_history but never prune old rows. Over time every user
--      accumulates an unbounded history. This trigger keeps exactly the
--      last 5 hashes per user, which matches PASSWORD_HISTORY_LIMIT in
--      the Edge Functions.
--
-- Fires: AFTER INSERT on password_history
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_password_history_trim()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  DELETE FROM password_history
  WHERE  user_id = NEW.user_id
    AND  id NOT IN (
           SELECT id
           FROM   password_history
           WHERE  user_id = NEW.user_id
           ORDER  BY created_at DESC
           LIMIT  5
         );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_password_history_trim
  AFTER INSERT ON password_history
  FOR EACH ROW
  EXECUTE FUNCTION fn_password_history_trim();

COMMENT ON FUNCTION fn_password_history_trim() IS
  'Automatically prunes password_history to the 5 most recent entries per user after every insert.';


-- ─────────────────────────────────────────────────────────────────────────────
-- TRIGGER 8: Set users.updated_at when account_status, force_password_change,
--            last_login_at, or fcm_token change
--
-- Why: Migration 00001 created a generic set_updated_at() trigger
--      (trg_users_updated_at) that already fires on ANY UPDATE.
--      The existing trigger is sufficient — no additional trigger is needed
--      here. This comment is left as documentation of the decision.
--
-- NOTE: The existing trg_users_updated_at in 00001 covers this case fully.
-- ─────────────────────────────────────────────────────────────────────────────


-- ─────────────────────────────────────────────────────────────────────────────
-- Sanity check: verify all trigger functions are installed
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  missing TEXT := '';
  fn_names TEXT[] := ARRAY[
    'fn_auth_update_last_login',
    'fn_auth_record_account_locked',
    'fn_otp_guard_account_status',
    'fn_otp_invalidate_previous',
    'fn_otp_log_max_attempts',
    'fn_users_log_force_password_changed',
    'fn_password_history_trim'
  ];
  fn TEXT;
BEGIN
  FOREACH fn IN ARRAY fn_names LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc
      JOIN pg_namespace ON pg_namespace.oid = pg_proc.pronamespace
      WHERE proname = fn
        AND nspname = 'public'
    ) THEN
      missing := missing || fn || ', ';
    END IF;
  END LOOP;

  IF missing <> '' THEN
    RAISE EXCEPTION 'Missing trigger functions: %', rtrim(missing, ', ');
  END IF;

  RAISE NOTICE 'All 7 auth trigger functions verified successfully.';
END;
$$;

COMMIT;
