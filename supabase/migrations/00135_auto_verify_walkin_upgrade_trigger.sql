-- =====================================================================
-- Migration: 00135_auto_verify_walkin_upgrade_trigger.sql
-- Purpose  : DB-level guarantee of the business rule: the moment an
--            in-office (walk-in) application becomes 'submitted' or
--            'converted', the linked lender's Account Upgrade MUST be
--            'verified' — staff collected and checked the identity
--            documents in person at the office, so there is nothing left
--            for the KYC review queue.
--
-- WHY a trigger (not just edge-function code):
--   • Every code path that writes in_office_applications.status is
--     covered automatically, including legacy paths that create the
--     lender account but skip the auto-verify step.
--   • No future submit flow can regress and leave the lender at
--     'not_submitted' while their walk-in application is already
--     submitted (the exact mismatch reported).
--
-- Safe / idempotent:
--   • Only fires when lender_id is set and status is a final walk-in
--     state ('submitted'/'converted'). An explicit staff 'rejected'
--     upgrade is never overwritten (in_office_applications has no such
--     status).
--   • Upsert (id + status + updated_at only) — never clobbers existing
--     profile fields. The trg_sync_lender_profiles_lookup BEFORE trigger
--     keeps account_upgrade_status_id in sync automatically.
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION auto_verify_walkin_lender_upgrade()
RETURNS trigger AS $$
BEGIN
  IF NEW.lender_id IS NOT NULL AND NEW.status IN ('submitted', 'converted') THEN
    INSERT INTO public.lender_profiles (id, account_upgrade_status, updated_at)
    VALUES (NEW.lender_id, 'verified', NOW())
    ON CONFLICT (id) DO UPDATE
      SET account_upgrade_status = 'verified',
          updated_at = NOW();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_verify_walkin_upgrade ON public.in_office_applications;
CREATE TRIGGER trg_auto_verify_walkin_upgrade
AFTER INSERT OR UPDATE OF status, lender_id ON public.in_office_applications
FOR EACH ROW
EXECUTE FUNCTION auto_verify_walkin_lender_upgrade();

COMMIT;
