-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00006_auth_sync_users.sql
-- Purpose   : When a user is created in auth.users (e.g. via the Supabase
--             Dashboard → Authentication → Add User), automatically create
--             the matching row in public.users as a HEAD MANAGER.
--             Combined with trg_users_single_head_manager, this also means
--             adding a second auth user is blocked at the DB level.
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
BEGIN
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
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user();

COMMIT;
