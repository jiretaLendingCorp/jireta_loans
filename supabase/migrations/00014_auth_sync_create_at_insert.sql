-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00014_auth_sync_create_at_insert.sql
-- Purpose   : FIX "Add User in Authentication still not in public.users".
--
-- Root cause (verified live): GoTrue writes raw_app_meta_data IN THE INITIAL
-- INSERT, NOT in a follow-up UPDATE (the 00007 note was a misdiagnosis). So:
--   * For a Dashboard "Add User" (no role metadata) the old UPDATE trigger
--     never fired and the INSERT trigger bailed whenever a head_manager
--     existed → the user silently got NO public.users row.
--   * Edge Functions create the row themselves and always pass a role in
--     app_metadata, which IS visible at INSERT time.
--
-- New behaviour: the sync runs at INSERT time.
--   * Row already exists  → Edge Function / OTP / Google already did it.
--   * Role in app_metadata → an Edge Function owns the row → skip.
--   * Google OAuth         → auth-google owns the row → skip.
--   * No role metadata     → Dashboard "Add User":
--       - no head_manager yet → head_manager (bootstrap)
--       - otherwise           → employee
--   Insert is idempotent (ON CONFLICT DO NOTHING) and errors are swallowed
--   so auth user creation can never fail because of the sync.
--
-- The UPDATE trigger is kept as a safety net in case metadata ever arrives
-- in a later update; the function body is identical for both paths.
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

  -- No role metadata → a Dashboard "Authentication → Add User" user.
  -- Bootstrap: very first user (no head_manager yet) → head_manager.
  -- Otherwise → employee.
  IF NOT v_has_hm THEN
    v_role_name := 'head_manager';
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

DROP TRIGGER IF EXISTS on_auth_user_updated ON auth.users;

CREATE TRIGGER on_auth_user_updated
  AFTER UPDATE OF raw_app_meta_data ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user();

COMMIT;