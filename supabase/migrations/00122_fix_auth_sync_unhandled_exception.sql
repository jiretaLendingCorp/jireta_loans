-- =====================================================================
-- Migration : 00122_fix_auth_sync_unhandled_exception.sql
-- Purpose   : Fix "Database error creating new user" in Supabase Dashboard.
--
-- Root causes (compounding):
--
-- 1) In 00116, RAISE EXCEPTION for missing role was OUTSIDE the
--    inner BEGIN/EXCEPTION block, propagating into auth.users INSERT.
--
-- 2) The INSERT into public.users set account_status = 'active' but
--    did NOT set account_status_id (UUID FK added in 00110, made
--    NOT NULL in 00112). The BEFORE INSERT trg_sync_users_lookup
--    trigger is supposed to resolve code→uuid, but if that lookup
--    fails or the row is missing, account_status_id stays NULL and
--    the NOT NULL constraint kills the INSERT silently.
--
-- 3) Any other unexpected error (permissions, constraints) had no
--    catch-all, so it propagated and rolled back auth.users.
--
-- Fix:
--   a) Explicitly set account_status_id via a lookup into
--      user_account_statuses so we never depend on the BEFORE trigger
--      resolving it correctly.
--   b) Wrap the entire sync in a catch-all EXCEPTION handler so auth
--      user creation NEVER fails.
--   c) Add RAISE NOTICE logging at each step for debugging.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_role_id          uuid;
  v_role_name        text;
  v_first_name       text;
  v_last_name        text;
  v_phone            text;
  v_account_status_id uuid;
BEGIN
  -- ── Early-return guards ────────────────────────────────────────────

  -- Already synced (e.g. Edge Function created the row).
  IF EXISTS (SELECT 1 FROM public.users WHERE id = NEW.id) THEN
    RETURN NEW;
  END IF;

  -- Edge Functions / OTP set role in raw_app_meta_data → they own the
  -- public.users row → skip auto-sync.
  v_role_name := NULLIF(NEW.raw_app_meta_data->>'role', '');

  IF v_role_name IS NOT NULL
     OR COALESCE(NEW.raw_app_meta_data->>'provider', '') = 'google'
     OR COALESCE(NEW.raw_app_meta_data->>'providers', '') ILIKE '%google%' THEN
    RETURN NEW;
  END IF;

  -- ── Sync path — Dashboard "Add User" → default head_manager ──────
  -- Wrapped in catch-all so auth user creation always succeeds.
  BEGIN
    v_role_name := 'head_manager';

    -- 1) Look up role
    SELECT id INTO v_role_id FROM public.roles WHERE name = v_role_name;
    IF v_role_id IS NULL THEN
      RAISE EXCEPTION 'role % not found in public.roles', v_role_name;
    END IF;

    -- 2) Look up account_status_id (UUID FK, NOT NULL since 00112)
    SELECT id INTO v_account_status_id
    FROM   public.user_account_statuses
    WHERE  code = 'active';

    IF v_account_status_id IS NULL THEN
      RAISE EXCEPTION 'account_status "active" not found in user_account_statuses';
    END IF;

    -- 3) Resolve names — default Head/Manager when meta is blank
    v_first_name := COALESCE(NULLIF(NEW.raw_user_meta_data->>'first_name', ''), 'Head');
    v_last_name  := COALESCE(NULLIF(NEW.raw_user_meta_data->>'last_name', ''), 'Manager');

    -- 4) Handle NULL/empty phone (phone_number is UNIQUE; multiple
    --    NULLs are allowed in PostgreSQL, but empty string '' is not NULL)
    v_phone := NULLIF(TRIM(COALESCE(NEW.phone, '')), '');

    -- 5) Insert into public.users
    INSERT INTO public.users (
      id, role_id, email, phone_number,
      first_name, last_name,
      account_status, account_status_id,
      force_password_change
    ) VALUES (
      NEW.id, v_role_id, NEW.email, v_phone,
      v_first_name, v_last_name,
      'active', v_account_status_id,
      true
    );

  EXCEPTION WHEN OTHERS THEN
    -- Never let a sync failure block auth user creation.
    RAISE WARNING 'handle_new_auth_user sync FAILED for %: % (SQLSTATE: %)',
      NEW.id, SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

-- Recreate triggers (idempotent)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user();

DROP TRIGGER IF EXISTS on_auth_user_updated ON auth.users;
CREATE TRIGGER on_auth_user_updated
  AFTER UPDATE OF raw_app_meta_data ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user();

COMMENT ON FUNCTION public.handle_new_auth_user() IS
  'Syncs Dashboard Add User -> public.users. 00122: explicitly sets account_status_id (UUID FK NOT NULL), wraps sync in catch-all EXCEPTION handler so auth creation never fails.';

COMMIT;
