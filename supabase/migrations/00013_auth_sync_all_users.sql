-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00013_auth_sync_all_users.sql
-- Purpose   : Fix "auth user created but never appears in public.users".
--
-- The previous trigger (00007) bailed out whenever a head_manager already
-- existed, so ANY user created after the bootstrap (e.g. from the Supabase
-- Dashboard → Authentication → Add User) silently got no public.users row.
--
-- New behaviour:
--   * If public.users already has the row (Edge Functions, OTP self-register
--     and Google OAuth all create their own rows) → do nothing.
--   * If app_metadata.role is set, or the provider is Google → do nothing
--     (the Edge Function / OAuth flow owns that row).
--   * No head_manager yet → auto-create as head_manager (bootstrap).
--   * No role metadata and a head_manager already exists → auto-create as
--     employee, so dashboard-created staff still land in public.users.
--
-- GoTrue writes app_metadata in a FOLLOW-UP UPDATE after the initial INSERT
-- (so an AFTER INSERT trigger sees role = NULL even for Edge-Function users).
-- That is why a second trigger on UPDATE OF raw_app_meta_data runs the same
-- sync once the metadata arrives. ON CONFLICT (id) DO NOTHING keeps every
-- path idempotent, and errors are swallowed so auth creation never fails.
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
  v_role_id    uuid;
  v_role_name  text;
  v_first_name text;
  v_last_name  text;
  v_has_hm     boolean;
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

  SELECT EXISTS (
    SELECT 1 FROM public.users u
    JOIN public.roles r ON r.id = u.role_id
    WHERE r.name = 'head_manager' AND u.account_status <> 'archived'
  ) INTO v_has_hm;

  -- Bootstrap: very first user (no head_manager yet) → head_manager.
  IF NOT v_has_hm THEN
    v_role_name := 'head_manager';
  -- At INSERT time GoTrue has NOT yet written app_metadata, so Edge-Function
  -- users still look role-less here. Bail out; the UPDATE trigger re-runs
  -- once raw_app_meta_data is written.
  ELSIF TG_OP = 'INSERT' THEN
    RETURN NEW;
  -- UPDATE timing with still no role metadata → a dashboard-created user.
  -- Give them an employee row instead of silently dropping them.
  ELSE
    v_role_name := 'employee';
  END IF;

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

-- GoTrue writes raw_app_meta_data in a follow-up UPDATE, so also sync then.
DROP TRIGGER IF EXISTS on_auth_user_updated ON auth.users;

CREATE TRIGGER on_auth_user_updated
  AFTER UPDATE OF raw_app_meta_data ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user();

COMMIT;