-- =====================================================================
-- Migration: 00116_fix_audit_performed_by_names.sql
-- Purpose  : Fix "missing PERFORMED BY" in Audit Logs (screenshot shows
--            Archive/Unarchive User, Report Export, Create Rider as "?"
--            with blank name). Root cause:
--
--   * 00006_auth_sync_users.sql defaulted Dashboard-created head_manager
--     names to 'Head'/'Manager'.
--   * 00014/00015 changed the trigger to default to '' (empty string):
--       v_first_name := COALESCE(NULLIF(meta->>'first_name',''), '');
--     So any head_manager (or employee) created via Supabase Dashboard
--     → Authentication → Add User after those migrations got empty
--     first_name/last_name. That empty name is what audit_logs joins to
--     via users!audit_logs_performed_by_fkey, so the UI computed:
--       performers '' + initials '?' (empty -> '?'), rendering blank cell.
--     CI/rider/lender users created via Edge Functions had proper names,
--     so they displayed correctly (e.g. "Romson rere" RR).
--
--   Fixes:
--     1) Restore trigger defaults to 'Head'/'Manager' so future Dashboard
--        users are never nameless (idempotent replace of handle_new_auth_user).
--     2) Backfill existing nameless users: head_manager -> Head Manager,
--        employee -> Employee (derived from email prefix if needed), others
--        keep email/phone fallback but ensure TRIM(name) != ''.
--     3) Document that audit-get-logs now selects email/phone for fallback.
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────
-- 1) Restore sensible defaults in the auth sync trigger
--    (overwrites 00015 version that used '' fallbacks)
-- ─────────────────────────────────────────────────────────────────
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
  IF EXISTS (SELECT 1 FROM public.users WHERE id = NEW.id) THEN
    RETURN NEW;
  END IF;

  v_role_name := NULLIF(NEW.raw_app_meta_data->>'role', '');

  IF v_role_name IS NOT NULL
     OR COALESCE(NEW.raw_app_meta_data->>'provider', '') = 'google'
     OR COALESCE(NEW.raw_app_meta_data->>'providers', '') ILIKE '%google%' THEN
    RETURN NEW;
  END IF;

  -- Dashboard "Add User" path — default to head_manager (or preserve
  -- single-HM semantics if you re-enable the guard).
  v_role_name := 'head_manager';

  SELECT id INTO v_role_id FROM public.roles WHERE name = v_role_name;
  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'role % not found in public.roles', v_role_name;
  END IF;

  -- Restore 00006 defaults: 'Head'/'Manager' instead of '' so audit
  -- PERFORMED BY never renders blank/'?'.
  v_first_name := COALESCE(NULLIF(NEW.raw_user_meta_data->>'first_name', ''), 'Head');
  v_last_name  := COALESCE(NULLIF(NEW.raw_user_meta_data->>'last_name', ''), 'Manager');

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

COMMENT ON FUNCTION public.handle_new_auth_user() IS
  'Syncs Dashboard Add User -> public.users. Restored 00116: defaults to Head Manager when first_name/last_name meta missing so audit logs PERFORMED BY never blank (fixes missing ? avatars).';

-- ─────────────────────────────────────────────────────────────────
-- 2) Backfill existing users that have empty/whitespace-only names
--    (head_manager -> Head Manager, employee -> derive from email)
-- ─────────────────────────────────────────────────────────────────
-- Head managers with blank names → Head Manager
UPDATE public.users
SET first_name = 'Head', last_name = 'Manager'
WHERE role_id = (SELECT id FROM public.roles WHERE name = 'head_manager')
  AND (first_name IS NULL OR btrim(first_name) = '')
  AND (last_name IS NULL OR btrim(last_name) = '');

-- Head managers with only one side blank (e.g. 'Head'/'') → fill missing side
UPDATE public.users
SET first_name = COALESCE(NULLIF(btrim(first_name), ''), 'Head'),
    last_name  = COALESCE(NULLIF(btrim(last_name), ''), 'Manager')
WHERE role_id = (SELECT id FROM public.roles WHERE name = 'head_manager')
  AND (btrim(COALESCE(first_name,'')) = '' OR btrim(COALESCE(last_name,'')) = '');

-- Employees with blank names → use email prefix as first_name, last_name = Employee
-- (better than blank '?' in audit; operators can PATCH via users-manage if needed)
UPDATE public.users
SET first_name = COALESCE(NULLIF(btrim(first_name), ''),
                   initcap(split_part(email, '@', 1))),
    last_name  = COALESCE(NULLIF(btrim(last_name), ''), 'Employee')
WHERE role_id = (SELECT id FROM public.roles WHERE name = 'employee')
  AND (btrim(COALESCE(first_name,'')) = '' OR btrim(COALESCE(last_name,'')) = '');

-- Generic safety: any other user with both names blank → fallback to email/phone snippet
UPDATE public.users
SET first_name = COALESCE(NULLIF(btrim(first_name), ''),
                   COALESCE(NULLIF(split_part(email, '@', 1), ''), 'User')),
    last_name  = COALESCE(NULLIF(btrim(last_name), ''),
                   substring(phone_number from 1 for 4))
WHERE (btrim(COALESCE(first_name,'')) = '' AND btrim(COALESCE(last_name,'')) = '')
  AND email IS NOT NULL;

COMMENT ON COLUMN public.users.first_name IS 'Given name; 00116 backfilled blank Dashboard users so audit_logs PERFORMED BY renders correctly.';
COMMENT ON COLUMN public.users.last_name  IS 'Family name; 00116 backfilled blank Dashboard users so audit_logs PERFORMED BY renders correctly.';

COMMIT;
