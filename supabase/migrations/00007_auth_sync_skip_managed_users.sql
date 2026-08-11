-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00007_auth_sync_skip_managed_users.sql
-- Purpose   : Fix "database error creating new user" — the on_auth_user_created
--             trigger fired on EVERY auth.users insert, including users the
--             Edge Functions create themselves. That insert tried to create a
--             HEAD MANAGER row, which the single-head-manager guard rejected.
--
--             Now the trigger only auto-creates the public.users row for
--             users created WITHOUT a role in app_metadata (i.e. via the
--             Supabase Dashboard → Authentication → Add User). Edge-function
--             and Google OAuth users set app_metadata.role / provider, so the
--             trigger skips them and the function handles the row itself.
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
  v_first_name text;
  v_last_name  text;
  v_app_role   text;
BEGIN
  -- Edge functions pass app_metadata.role ('employee' | 'rider' | 'lender')
  -- and create the public.users row themselves → skip auto-sync.
  v_app_role := NULLIF(NEW.raw_app_meta_data->>'role', '');

  -- Google OAuth users are created by GoTrue and mapped to a lender row by
  -- the auth-google Edge Function → skip auto-sync too.
  IF v_app_role IS NOT NULL
     OR COALESCE(NEW.raw_app_meta_data->>'provider', '') = 'google'
     OR COALESCE(NEW.raw_app_meta_data->>'providers', '') ILIKE '%google%' THEN
    RETURN NEW;
  END IF;

  -- Dashboard-created user (no role metadata) → auto-create as head_manager.
  SELECT id INTO v_role_id FROM roles WHERE name = 'head_manager';
  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'head_manager role not found in public.roles';
  END IF;

  v_first_name := COALESCE(NULLIF(NEW.raw_user_meta_data->>'first_name', ''), 'Head');
  v_last_name  := COALESCE(NULLIF(NEW.raw_user_meta_data->>'last_name', ''), 'Manager');

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

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user();

COMMIT;
