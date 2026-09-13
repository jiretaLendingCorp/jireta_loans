-- =====================================================================
-- Migration : 00156_active_sessions_consistent_clock.sql
-- Purpose   : Isang orasan lang ang gamitin ng single-active-session logic.
--
-- Problema (sanhi ng MALING "Session Ended — signed in on another device"):
--   Dalawang magkaibang orasan ang nagsusulat sa `active_sessions.last_seen_at`:
--
--     * RPC (`claim_active_session` / `validate_active_session`) — gumagamit ng
--       `now_manila()` na `NOW() AT TIME ZONE 'Asia/Manila' AT TIME ZONE 'UTC'`.
--       Iyon ay instant na WALONG ORAS SA HINAHARAP (Manila wall-clock na
--       itinuring na UTC).
--     * Edge Function (`auth-session` refresh bump) — `nowManilaISO()` na
--       TUNAY na UTC (tamang instant).
--
--   Dahil sa paghahalo, sira ang 5-minute "freshness" rule ng
--   first-login-wins: ang row na huling na-touch ng RPC ay mukhang sariwa nang
--   hanggang 8 oras (patay na device pero bumablock pa rin sa bagong login),
--   at ang row na na-touch ng Edge Function ay mukhang patay agad (buhay na
--   device pero napapaalis ng ibang login). Parehong nagreresulta sa maling
--   "signed in on another device" sa user.
--
-- Ayos:
--   1) TUNAY na instant (`NOW()`) na lang ang gamitin ng dalawang session
--      functions — pareho na sa `nowManilaISO()` ng Edge Functions.
--   2) I-clear ang lahat ng rows (gaya ng 00142): lahat ng existing rows ay
--      gawa ng magkahalong orasan, kaya hindi mapagkakatiwalaan ang
--      `last_seen_at` nila. Ang table na ito ay lock-table lang — ang susunod
--      na login ay mag-cla-claim ng sariwang row.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ── 1) Clean slate ────────────────────────────────────────────────────
-- Walang device na manghahawakan ng row na gawa ng luma/magkahalong orasan.
DELETE FROM public.active_sessions;

-- ── 2) claim_active_session — NOW() ang basehan ────────────────────────
-- First-login-wins pa rin: kapag may IBANG session na sariwa (heartbeat sa
-- loob ng 5 minuto), tatanggi ito at HINDI nire-revoke ang iba. Ang bagong
-- device ang walang row (at malinaw nang SESSION_ACTIVE_ELSEWHERE ang isasagot
-- ng login — hindi na "successful login tapos kicked").
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

  PERFORM 1 FROM public.active_sessions
  WHERE user_id = p_user_id
    AND session_identifier IS DISTINCT FROM p_session_identifier
    AND revoked_at IS NULL
    AND last_seen_at > NOW() - INTERVAL '5 minutes'
  LIMIT 1;

  IF FOUND THEN
    RETURN FALSE;
  END IF;

  INSERT INTO public.active_sessions (
    user_id, session_identifier, created_at, last_seen_at, revoked_at
  )
  VALUES (
    p_user_id, p_session_identifier, NOW(), NOW(), NULL
  )
  ON CONFLICT (user_id) DO UPDATE
  SET session_identifier = EXCLUDED.session_identifier,
      created_at = EXCLUDED.created_at,
      last_seen_at = EXCLUDED.last_seen_at,
      revoked_at = NULL;

  RETURN TRUE;
END;
$$;

-- ── 3) validate_active_session — NOW() ang basehan ─────────────────────
CREATE OR REPLACE FUNCTION public.validate_active_session(
  p_user_id UUID,
  p_session_identifier TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  matched_count INTEGER;
BEGIN
  UPDATE public.active_sessions
  SET last_seen_at = NOW()
  WHERE user_id = p_user_id
    AND session_identifier = p_session_identifier
    AND revoked_at IS NULL;

  GET DIAGNOSTICS matched_count = ROW_COUNT;
  RETURN matched_count > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_active_session(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.validate_active_session(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_active_session(UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.validate_active_session(UUID, TEXT) TO service_role;

COMMIT;
