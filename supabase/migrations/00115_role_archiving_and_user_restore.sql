-- =====================================================================
-- Migration: 00115_role_archiving_and_user_restore.sql
-- Purpose  : Implement ROLE-level archiving + complete USER archive/restore
--            lifecycle per requirement:
--            "KAPAG NAKA ARCHIVED UNG ROLE OR USER DAPAT HINDI MAGAGAMIT
--             NI USER UNG ACCOUNT NIYA PERO KAPAG NA UNARCHIVED NA THEN
--             MA RERESTORE NA UNG ACCOUNT MAGAGAMIT NA NI USER"
--
--            ARCHIVED role or user -> account blocked (login, OTP, refresh,
--            any authenticated request). UNARCHIVED -> restored & usable.
--
--            Changes:
--              1) roles: add is_archived + archived_at
--              2) Update auth_role() to respect role archival + user archival
--              3) Update OTP guard to block archived roles
--              4) Add helper is_role_archived() for edge functions
--              5) Ensure audit trail via existing audit_logs
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────
-- 1) roles: add archiving columns (idempotent)
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE public.roles
  ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.roles
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;

ALTER TABLE public.roles
  ADD COLUMN IF NOT EXISTS archived_by UUID REFERENCES public.users(id);

COMMENT ON COLUMN public.roles.is_archived IS 'When TRUE, ALL users with this role are blocked from login/use (OTP, email/password, Google, refresh, any authenticated request). Unarchiving (FALSE) instantly restores access without touching each users row. HEAD_MANAGER cannot be archived. Synced with application-level auth checks.';
COMMENT ON COLUMN public.roles.archived_at IS 'Timestamp when role was archived (NULL when active). Set automatically by archive/unarchive edge functions.';
COMMENT ON COLUMN public.roles.archived_by IS 'User who archived the role (head_manager).';

CREATE INDEX IF NOT EXISTS idx_roles_is_archived ON public.roles(is_archived) WHERE is_archived = TRUE;

-- ─────────────────────────────────────────────────────────────────
-- 2) Helper: check if a role is archived by id or name
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_role_archived(p_role_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  SELECT COALESCE((SELECT is_archived FROM public.roles WHERE id = p_role_id), FALSE);
$$;

CREATE OR REPLACE FUNCTION public.is_role_archived_by_name(p_role_name TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  SELECT COALESCE((SELECT is_archived FROM public.roles WHERE name = p_role_name), FALSE);
$$;

COMMENT ON FUNCTION public.is_role_archived(UUID) IS 'Returns TRUE if role id is archived. Used by edge functions to block archived-role logins.';
COMMENT ON FUNCTION public.is_role_archived_by_name(TEXT) IS 'Returns TRUE if role name is archived.';

-- ─────────────────────────────────────────────────────────────────
-- 3) Update auth_role() — RLS helper used by ~20 policies
--    Now checks BOTH user account_status=active AND role not archived.
--    Returns NULL (no role) if either is archived -> RLS denies access.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.auth_role()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  SELECT r.name
  FROM public.users u
  JOIN public.roles r ON r.id = u.role_id
  WHERE u.id = auth.uid()
    AND u.account_status = 'active'
    AND COALESCE(r.is_archived, FALSE) = FALSE
  LIMIT 1;
$$;
COMMENT ON FUNCTION public.auth_role() IS 'Returns role name of authenticated user (head_manager/employee/rider/lender). Returns NULL if user is not active OR role is archived -> RLS policies will deny. SECURITY DEFINER. Updated 00115 to enforce role archiving. Checks account_status=active (synced with account_status_id) + roles.is_archived=FALSE.';

-- ─────────────────────────────────────────────────────────────────
-- 4) OTP guard — also block if role is archived
--    Existing trigger fn_otp_guard_account_status checks user status.
--    Extend to check role archival so archived-role users cannot receive OTP.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_otp_guard_account_status()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_status VARCHAR(20);
  v_role_archived BOOLEAN;
BEGIN
  SELECT u.account_status, COALESCE(r.is_archived, FALSE)
  INTO   v_status, v_role_archived
  FROM   public.users u
  JOIN   public.roles r ON r.id = u.role_id
  WHERE  u.phone_number = NEW.phone_number
  LIMIT  1;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF v_role_archived THEN
    RAISE EXCEPTION 'Cannot send OTP — role is archived'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_status IN ('archived', 'inactive') THEN
    RAISE EXCEPTION 'Cannot send OTP — account is %', v_status
      USING ERRCODE = 'P0002';
  END IF;

  RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.fn_otp_guard_account_status() IS 'OTP guard updated 00115: blocks OTP for archived/inactive users AND users whose role is archived.';

-- ─────────────────────────────────────────────────────────────────
-- 5) Prevent archiving head_manager role at DB level + auto timestamps
--    (Edge function also enforces, this is defense-in-depth)
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_roles_archive_guard()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.is_archived = TRUE AND COALESCE(OLD.is_archived, FALSE) = FALSE THEN
    IF OLD.name = 'head_manager' THEN
      RAISE EXCEPTION 'Cannot archive head_manager role'
        USING ERRCODE = '42501';
    END IF;
    NEW.archived_at := NOW();
  ELSIF NEW.is_archived = FALSE AND COALESCE(OLD.is_archived, FALSE) = TRUE THEN
    NEW.archived_at := NULL;
    NEW.archived_by := NULL;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_roles_archive_guard ON public.roles;
CREATE TRIGGER trg_roles_archive_guard
  BEFORE UPDATE OF is_archived ON public.roles
  FOR EACH ROW EXECUTE FUNCTION public.fn_roles_archive_guard();

COMMENT ON FUNCTION public.fn_roles_archive_guard() IS 'Guard: prevents archiving head_manager role; auto-sets/clears archived_at. Added 00115.';

-- ─────────────────────────────────────────────────────────────────
-- 6) Ensure users cannot be created with archived role (defense)
--    Add trigger on users insert/update of role_id
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_users_guard_archived_role()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_archived BOOLEAN;
BEGIN
  SELECT COALESCE(is_archived, FALSE) INTO v_archived FROM public.roles WHERE id = NEW.role_id;
  IF v_archived THEN
    RAISE EXCEPTION 'Cannot assign archived role % to user', (SELECT name FROM public.roles WHERE id = NEW.role_id)
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_users_guard_archived_role ON public.users;
CREATE TRIGGER trg_users_guard_archived_role
  BEFORE INSERT OR UPDATE OF role_id ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.fn_users_guard_archived_role();
COMMENT ON FUNCTION public.fn_users_guard_archived_role() IS 'Prevents assigning an archived role to a user. Added 00115.';

-- ─────────────────────────────────────────────────────────────────
-- 7) RLS / audit sanity: ensure archived users/roles rows still visible
--    to head_manager for management (no policy change needed — service_role
--    edge functions bypass RLS). Just document intent.
-- ─────────────────────────────────────────────────────────────────

COMMIT;
