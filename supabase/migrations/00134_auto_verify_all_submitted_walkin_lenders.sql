-- =====================================================================
-- Migration: 00134_auto_verify_all_submitted_walkin_lenders.sql
-- Purpose  : Business rule — whenever an in-office (walk-in) application
--            has been submitted/converted, the lender's Account Upgrade
--            must be VERIFIED (staff collected and checked the identity
--            documents in person at the office, so there is nothing left
--            for the KYC review queue).
--
--            00131 already auto-verified walk-in lenders still stuck at
--            'not_submitted', but accounts created through later paths
--            (submit-account retries, interrupted runs, self-registered
--            lenders later linked to a walk-in application) can be left
--            in 'pending'/'submitted'/'not_submitted' while their
--            application is already submitted. This backfill converges
--            every such lender to 'verified'.
--
-- Safe / idempotent:
--   • Only touches lenders that have an in_office_applications row
--     (lender_id set) with status submitted/converted.
--   • Only upgrades non-final states ('not_submitted', 'pending',
--     'submitted'). An explicit staff 'rejected' is NEVER overridden.
--   • The sync_generic_lookup / trg_sync_lender_profiles_lookup trigger
--     keeps account_upgrade_status_id in sync automatically; the explicit
--     alias update below is belt-and-braces (same as 00131).
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

UPDATE public.lender_profiles lp
SET account_upgrade_status = 'verified',
    updated_at             = NOW()
WHERE lp.account_upgrade_status IN ('not_submitted', 'pending', 'submitted')
  AND EXISTS (
    SELECT 1
    FROM public.in_office_applications ioa
    WHERE ioa.lender_id = lp.id
      AND ioa.status IN ('submitted', 'converted')
  );

-- Also ensure the uuid alias column is populated for the rows we just set
-- (idempotent backfill; trigger normally handles this, belt-and-braces).
UPDATE public.lender_profiles lp
SET account_upgrade_status_id = aus.id
FROM public.account_upgrade_statuses aus
WHERE aus.code = 'verified'
  AND lp.account_upgrade_status = 'verified'
  AND lp.account_upgrade_status_id IS DISTINCT FROM aus.id;

COMMIT;
