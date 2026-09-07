-- =====================================================================
-- Migration: 00131_auto_verify_walkin_lenders.sql
-- Purpose  : Auto-verify lender accounts created through the in-office
--            (walk-in) flow that were left at 'not_submitted'.
--
-- WHY: The in-office wizard is staff-assisted — the staff collects and
-- checks the identity documents in person at Step 3 (Documents), so the
-- lender account must be VERIFIED immediately. Edge functions now upsert
-- lender_profiles with account_upgrade_status='verified', but accounts
-- created BEFORE that change were inserted with 'not_submitted' and would
-- otherwise sit in the KYC queue forever (and block loan creation via the
-- old pause path). This backfill repairs those legacy walk-in lenders.
--
-- Safe / idempotent:
--   • Only touches lenders that have an in_office_applications row
--     (lender_id set) with status submitted/converted — i.e. the walk-in
--     flow already progressed past account creation.
--   • Only upgrades lenders currently 'not_submitted' — never downgrades
--     rejected/submitted/pending accounts that are being reviewed.
--   • The sync_generic_lookup / trg_sync_lender_profiles_lookup trigger
--     keeps account_upgrade_status_id in sync automatically.
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

-- Verify walk-in lenders that are still 'not_submitted' (legacy pre-auto-verify).
UPDATE public.lender_profiles lp
SET account_upgrade_status = 'verified',
    updated_at             = NOW()
WHERE lp.account_upgrade_status = 'not_submitted'
  AND EXISTS (
    SELECT 1
    FROM public.in_office_applications ioa
    WHERE ioa.lender_id = lp.id
      AND ioa.status IN ('submitted', 'converted')
  );

-- Also ensure the uuid alias column is populated for the rows we just set
-- (idempotent backfill; trigger normally handles this, this is belt-and-braces).
UPDATE public.lender_profiles lp
SET account_upgrade_status_id = aus.id
FROM public.account_upgrade_statuses aus
WHERE aus.code = 'verified'
  AND lp.account_upgrade_status = 'verified'
  AND lp.account_upgrade_status_id IS DISTINCT FROM aus.id;

-- ─────────────────────────────────────────────────────────────────
-- Address fix: walk-in home addresses were inserted with is_primary=FALSE
-- (old code did not set the flag), so KYC details / profile address
-- lookups — which filter is_primary=true — returned no address.
-- Mark the home address of every walk-in lender as primary. Only the
-- home address is touched; any explicit primary is left untouched.
-- ─────────────────────────────────────────────────────────────────
UPDATE public.addresses a
SET is_primary = true,
    updated_at = NOW()
WHERE a.address_type = 'home'
  AND a.is_primary = false
  AND EXISTS (
    SELECT 1
    FROM public.in_office_applications ioa
    WHERE ioa.lender_id = a.user_id
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.addresses a2
    WHERE a2.user_id = a.user_id
      AND a2.is_primary = true
  );

COMMIT;