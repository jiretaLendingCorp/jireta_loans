-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00015_auth_sync_head_manager_default.sql
-- Purpose   : Dashboard "Authentication → Add User" users now become
--             HEAD MANAGER by default (not employee).
--
--   * Drops the single-head-manager guard (00005) so more than one
--     head_manager is allowed — otherwise every user after the first
--     dashboard add would be rejected and silently get no public.users row.
--   * Updates handle_new_auth_user(): a user created with no role in
--     app_metadata (i.e. the Supabase dashboard Add User) is created as
--     head_manager.
--   * Edge Functions / OTP / Google flows are untouched (they pass a role
--     in app_metadata and create their own public.users row).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- Remove the "only one head manager" guard so dashboard-added users can
-- become head_manager even when one already exists.
DROP TRIGGER IF EXISTS trg_users_single_head_manager ON public.users;
DROP FUNCTION IF EXISTS fn_users_single_head_manager();

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_role_id    uuid;
  v_role_name  text;
  v_first_name text;
  v_last_name  text;
BEGIN
  -- Edge Functions / OTP / Google create their own public.users rows.
  IF EXISTS (SELECT 1 FROM public.users WHERE id = NEW.id) THEN
    RETURN NEW;
  END IF;

  v_role_name := NULLIF(NEW.raw_app_meta_data->>'role', '');

  -- Role metadata present (or Google OAuth) → the owning flow inserts the row.
  IF v_role_name IS NOT NULL
     OR COALESCE(NEW.raw_app_meta_data->>'provider', '') = 'google'
     OR COALESCE(NEW.raw_app_meta_data->>'providers', '') ILIKE '%google%' THEN
    RETURN NEW;
  END IF;

  -- No role metadata → a Dashboard "Authentication → Add User" user.
  -- Default them to head_manager.
  v_role_name := 'head_manager';

  SELECT id INTO v_role_id FROM public.roles WHERE name = v_role_name;
  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'role % not found in public.roles', v_role_name;
  END IF;

  v_first_name := COALESCE(NULLIF(NEW.raw_user_meta_data->>'first_name', ''), '');
  v_last_name  := COALESCE(NULLIF(NEW.raw_user_meta_data->>'last_name', ''), '');

  BEGIN
    INSERT INTO public.users (
      id, role_id, email, phone_number,
      first_name, last_name, account_status,
      force_password_change
    ) VALUES (
      NEW.id, v_role_id, NEW.email, NEW.phone,
      v_first_name, v_last_name, 'active',
      true
    )
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    -- Never let a sync failure block auth user creation.
    NULL;
  END;

  RETURN NEW;
END;
$$;

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

COMMIT;