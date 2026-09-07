-- =====================================================================
-- Migration: 00132_no_force_pwd_change_lender_rider.sql
-- Purpose  : Enforce the system rule "walang temporary password at
--            force change password sa lender and rider role" — lender and
--            rider accounts are NOT forced to change their password on
--            next login. Account creation now writes
--            force_password_change=false (users-create, in-office-view);
--            this backfill clears the flag for lender/rider accounts that
--            were created before the rule so they are not blocked by the
--            Force Change Password screen.
--
-- Head Manager and Employee accounts keep the forced-change behavior.
-- Idempotent: only flips TRUE -> FALSE for lender/rider roles.
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

UPDATE public.users u
SET force_password_change = false
WHERE u.force_password_change = true
  AND EXISTS (
    SELECT 1
    FROM public.roles r
    WHERE r.id = u.role_id
      AND r.name IN ('lender', 'rider')
  );

COMMIT;