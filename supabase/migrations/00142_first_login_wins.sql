-- =====================================================================
-- Migration : 00142_first_login_wins.sql
-- Purpose   : Flip the single-active-session rule to FIRST-LOGIN-WINS.
--
-- Old rule (last-login-wins): a new login REVOKED the previous device's
-- session, so the older device got "Session Ended" and the new one took
-- over. Any re-login could kick the other device (ping-pong), and any
-- leftover row made BOTH devices get "Session Ended".
--
-- New rule (first-login-wins / lockout):
--   - While an ACTIVE, RECENTLY-SEEN session exists for the account, a
--     login from a DIFFERENT device does NOT take over and does NOT revoke
--     it. The new login gets NO row, so its very first authenticated
--     request returns SESSION_REVOKED → THAT device gets "Session Ended".
--   - The original device keeps working untouched.
--   - When the active device logs out, its row is revoked and the account
--     is free for the next login.
--   - A same-device re-login / refresh (same session_identifier) still
--     re-claims its own row.
--   - HEARTBEAT: the app pings auth-session?fn=ping ~every 60s while
--     open (validate_active_session bumps last_seen_at), so an open app
--     keeps blocking other logins indefinitely. A session not seen for
--     5 minutes (force-closed app, stale leftover from an older build,
--     abandoned row) no longer blocks a new login — the account can
--     never be locked by a dead session.
--   - Clean slate: any rows left over from the old rule are deleted.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- Leftover rows from the previous (last-login-wins) model would refuse the
-- very first login after this migration. Start clean.
DELETE FROM public.active_sessions;

CREATE OR REPLACE FUNCTION public.claim_active_session(
  p_user_id UUID,
  p_session_identifier TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF p_user_id IS NULL OR p_session_identifier IS NULL
     OR btrim(p_session_identifier) = '' THEN
    RETURN FALSE;
  END IF;

  -- First-login-wins: if a DIFFERENT, still-active, recently-seen session
  -- owns this account, refuse the claim. The active session is NOT revoked;
  -- the caller's session simply gets no row, so its first request will be
  -- rejected with SESSION_REVOKED (the new device is the one logged out).
  PERFORM 1 FROM public.active_sessions
  WHERE user_id = p_user_id
    AND session_identifier IS DISTINCT FROM p_session_identifier
    AND revoked_at IS NULL
    AND last_seen_at > now_manila() - INTERVAL '5 minutes'
  LIMIT 1;

  IF FOUND THEN
    RETURN FALSE;
  END IF;

  -- No other fresh active session: upsert this identifier (same-device
  -- re-login refreshes its own row; stale/revoked rows are replaced).
  INSERT INTO public.active_sessions (
    user_id, session_identifier, created_at, last_seen_at, revoked_at
  )
  VALUES (
    p_user_id, p_session_identifier, now_manila(), now_manila(), NULL
  )
  ON CONFLICT (user_id) DO UPDATE
  SET session_identifier = EXCLUDED.session_identifier,
      created_at = EXCLUDED.created_at,
      last_seen_at = EXCLUDED.last_seen_at,
      revoked_at = NULL;

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_active_session(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_active_session(UUID, TEXT) TO service_role;

COMMIT;