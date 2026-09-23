-- =====================================================================
-- Jireta Loans & Credit Corp
-- Migration : 00174_service_role_grants_session_hardening.sql
-- Purpose   : Ayusin ang "permission denied" (42501) ng Edge Functions sa
--             mga bagong table/function, at ang "23503" (FK) ng
--             `active_sessions`.
--
-- BAKIT (ayon sa Postgres logs ng 2026-09-23):
--   1) `permission denied for table active_sessions` — paulit-ulit tuwing
--      heartbeat (~60s) ng `auth-session?fn=ping`.
--
--      Ang `active_sessions` (00141) ay nabuo na may `REVOKE ALL ON TABLE
--      public.active_sessions FROM PUBLIC;` LANG. Dating sapat iyon dahil
--      awtomatikong binibigyan ng default privileges ng Supabase ang anon /
--      authenticated / service_role ng SELECT, INSERT, UPDATE, DELETE sa
--      bawat bagong table sa public.
--
--      NGAYON HINDI NA: sa mga bagong default ng platform hindi na
--      "auto-exposed" ang mga bagong table (config.toml →
--      `auto_expose_new_tables`, "When unset, new entities are NOT
--      auto-exposed, matching the new cloud default"). Kaya ang
--      `active_sessions` ay WALANG anumang privilege para sa `service_role`
--      — kahit na RLS-bypass nito, hindi ito lumalampas sa GRANT — kaya ang
--      bawat `db.from('active_sessions')` sa requireAuth / auth-session /
--      auth-logout ay 42501.
--
--      Ayos: tahasang ibigay (explicit GRANT) ang kailangan ng service_role
--      para sa lahat ng bagay sa public, at itakda ang parehong default para
--      sa mga bagay na BUBUOIN pa (para hindi na maulit ang klaseng ito ng
--      bug sa susunod na migration).
--
--   2) `insert or update on table "active_sessions" violates foreign key
--      constraint "active_sessions_user_id_fkey"` (23503).
--
--      Ang `claim_active_session` ay tumatanggap ng `p_user_id` at
--      nag-i-insert agad. Kapag ang id ay galing sa `auth.users` na WALANG
--      katumbas na row sa `public.users` (auth↔public desync — hal. account
--      na ginawa diretso sa Auth dashboard, o na-delete na public row na
--      buhay pa ang session), ang FK ang sasabog imbes na maayos na
--      pagtanggi. Ang 23503 ay hindi kasama sa "clean false" ng
--      single-session logic, kaya nagiging infra error ito sa logs.
--
--      Ayos: suriin muna ng function kung may `public.users` row; kung wala,
--      `RETURN FALSE` (fail-closed para sa row na ito, hindi exception).
--
-- Diagnostics (patakbuhin kung gusto mong hanapin ang mga desynced account):
--   select au.id as auth_id, au.email, au.phone
--   from auth.users au
--   left join public.users pu on pu.id = au.id
--   where pu.id is null;
--
-- Idempotent: GRANT/REVOKE + CREATE OR REPLACE lamang.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ── 1) service_role: tahasang privileges sa lahat ng nasa public ──────
-- Ang service_role (Edge Functions) ay may BYPASSRLS pero HINDI lumalampas
-- sa table/function GRANTs — kaya kailangan ito sa lahat ng object na bagong
-- buo pagkatapos ng 00003 (active_sessions, email_verifications, user_mpins,
-- at iba pa).
GRANT USAGE ON SCHEMA public TO service_role;

GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL ROUTINES  IN SCHEMA public TO service_role;

-- Default privileges para sa mga object na BUBUOIN PA ng role na
-- nagpapatakbo ng migration na ito (gaya ng 00003, para hindi na maulit).
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES    TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON ROUTINES  TO service_role;

-- ── 2) Panatilihing SARADO sa client roles ang internal tables ────────
-- Tanging service_role ang dapat humipo sa single-session lock table.
-- (Ang ibang internal tables ay may sariling REVOKE na sa 00022/00023/
-- 00024/00104/00117/00170/00172 — hindi na natin gagalawin ang malawak na
-- grants ng app sa mga normal na table tulad ng `users` / `roles` /
-- `notifications`, na siyang binabasa ng app sa PostgREST.)
REVOKE ALL ON TABLE public.active_sessions FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.active_sessions TO service_role;

-- ── 3) claim_active_session — tanggihan ang WALANG public.users row ────
-- Parehong first-login-wins na rule ng 00156 (NOW() ang orasan), dagdag lang
-- ang existence check para hindi sumabog sa FK (23503).
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

  -- Ang user_id ay dapat may row sa public.users. Ang isang auth.users id na
  -- walang katumbas (desync / deleted account) ay dati nagsasabog ng 23503
  -- (active_sessions_user_id_fkey) sa logs; ngayon malinis na FALSE.
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE LOG 'claim_active_session: walang public.users row para sa % — tinanggihan', p_user_id;
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

-- ── 4) validate_active_session — huwag na ring mag-touch sa wala ───────
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
  IF p_user_id IS NULL OR p_session_identifier IS NULL
     OR btrim(p_session_identifier) = '' THEN
    RETURN FALSE;
  END IF;

  UPDATE public.active_sessions
  SET last_seen_at = NOW()
  WHERE user_id = p_user_id
    AND session_identifier = p_session_identifier
    AND revoked_at IS NULL;

  GET DIAGNOSTICS matched_count = ROW_COUNT;
  RETURN matched_count > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_active_session(UUID, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.validate_active_session(UUID, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_active_session(UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.validate_active_session(UUID, TEXT) TO service_role;

-- ── 5) Verification (notices lang, hindi nakakasira) ──────────────────
DO $$
DECLARE
  v_missing TEXT;
BEGIN
  SELECT string_agg(privilege_type, ', ')
  INTO v_missing
  FROM (
    SELECT unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE']) AS privilege_type
    EXCEPT
    SELECT privilege_type
    FROM information_schema.role_table_grants
    WHERE table_schema = 'public'
      AND table_name = 'active_sessions'
      AND grantee = 'service_role'
  ) t;

  IF v_missing IS NULL THEN
    RAISE NOTICE 'OK: service_role ay may SELECT/INSERT/UPDATE/DELETE sa public.active_sessions';
  ELSE
    RAISE WARNING 'KULANG ang service_role grants sa active_sessions: %', v_missing;
  END IF;

  IF has_function_privilege('service_role', 'public.claim_active_session(uuid,text)', 'EXECUTE')
     AND has_function_privilege('service_role', 'public.validate_active_session(uuid,text)', 'EXECUTE') THEN
    RAISE NOTICE 'OK: service_role ay may EXECUTE sa claim/validate_active_session';
  ELSE
    RAISE WARNING 'KULANG ang EXECUTE grants ng service_role sa session functions';
  END IF;
END $$;

COMMIT;
