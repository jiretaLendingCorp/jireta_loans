-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00035_third_audit_fixes.sql
-- Purpose   : Fixes for the items from the third audit round that
--             survived verification.
--
--   Applied here:
--     1) loan_documents_read: add the rider branch. Riders already read
--        loans / loan_schedules via rider_assigned_loan_ids(); they
--        could not read the loan's documents. Consistency fix.
--     2) Drop rider_locations.active_assignment_id + assignment_type.
--        Verified dead code end-to-end:
--          - location-manage upsert writes only rider_id/lat/lng/
--            accuracy/updated_at (index.ts ~L122)
--          - every reader selects only those same columns (~L294, ~L479)
--          - the tracking UI's assignment_type is COMPUTED per request
--            from collection_assignments / credit_investigations /
--            disbursements (location-manage ~L160-252), not stored here
--        Removing them eliminates the unenforceable polymorphic UUID
--        instead of building FK scaffolding nobody uses.
--
--   Verified NOT applied (stale claims, third report):
--     - Circular FK loans <-> in_office_applications KEPT: both
--       directions are load-bearing (in-office-view embeds via
--       in_office_applications_loan_id_fkey; kpi-view/loans-view embed
--       via fk_loans_in_office; conversion writes loan_id). No delete
--       paths exist in the product.
--     - payments context CHECK already exists (00029,
--       payments_context_check) and is in the remote migration history.
--     - UNIQUE(role_id,permission_id) / UNIQUE(loan_id,co_maker_id)
--       already exist (00001).
--     - wizard_step already CHECK (BETWEEN 1 AND 5) (00001); the
--       suggested 1..7 does not match the actual 5-step wizard.
--     - notifications mark-read works via notifications-view?fn=mark-read
--       (PATCH, service_role) — no client UPDATE policy wanted.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) loan_documents_read — include riders assigned to the loan
-- ─────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS loan_documents_read ON loan_documents;
CREATE POLICY loan_documents_read ON loan_documents
  FOR SELECT TO authenticated
  USING (
    loan_id IN (SELECT auth_own_loan_ids())
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'rider'
      AND loan_id IN (SELECT rider_assigned_loan_ids())
    )
  );

-- ─────────────────────────────────────────────────────────────────────
-- 2) Drop the dead polymorphic reference columns
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE rider_locations
  DROP COLUMN IF EXISTS active_assignment_id,
  DROP COLUMN IF EXISTS assignment_type;

COMMIT;
