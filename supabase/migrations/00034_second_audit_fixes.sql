-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00034_second_audit_fixes.sql
-- Purpose   : Fixes for the items from the second audit report that
--             survived verification against the live schema/code.
--
--   Applied here:
--     1) DROP lender_profiles_no_direct_write — a PERMISSIVE ALL block
--        policy is redundant (RLS default-denies commands with no
--        matching policy) and dangerous: any future PERMISSIVE write
--        policy would OR past it. Cannot be made RESTRICTIVE without
--        breaking reads (RESTRICTIVE ANDs into the SELECT policy).
--     2) Missing scoped SELECT policies for loan_documents,
--        co_maker_documents, payment_reversals, terms_consent_logs —
--        parity with ci_documents/account_upgrade_documents. Purely
--        additive; edge functions use service_role and are unaffected.
--     3) collection_type normalized TEXT -> VARCHAR(20) to match every
--        other vocabulary column (binary-coercible, no rewrite).
--
--   Verified NOT applied (stale or would break production code):
--     - Circular FK loans <-> in_office_applications KEPT: both
--       directions are load-bearing. kpi-view/loans-view embed via
--       fk_loans_in_office; in-office-view embeds via
--       in_office_applications_loan_id_fkey and the conversion flow
--       writes loan_id. No delete paths exist in the product.
--     - payments context CHECK already exists (00029).
--     - UNIQUE(role_id,permission_id) and UNIQUE(loan_id,co_maker_id)
--       already exist (00001).
--     - wizard_step already CHECK (BETWEEN 1 AND 5) (00001).
--     - Status/type columns already hard-FK to lookup .code columns.
--     - notifications mark-read goes through the notifications-mark-read
--       edge function (service_role), so no client UPDATE policy is
--       wanted — adding one would deviate from the write architecture.
--     - rider_locations.active_assignment_id polymorphism is a known
--       design tradeoff; changing it requires location-manage changes,
--       not just SQL.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) Remove the redundant PERMISSIVE ALL block policy.
--    INSERT/UPDATE/DELETE on lender_profiles stay denied because no
--    permissive policy grants them (default deny). Writes remain the
--    exclusive domain of service_role edge functions.
-- ─────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS lender_profiles_no_direct_write ON lender_profiles;

-- ─────────────────────────────────────────────────────────────────────
-- 2) Missing read policies (SELECT-only; writes stay service_role).
--    DROP IF EXISTS first so the migration is re-runnable against a
--    remote that may already carry hand-applied versions.
-- ─────────────────────────────────────────────────────────────────────

-- Loan documents: lender sees docs of own loans; HM/Employee all.
DROP POLICY IF EXISTS loan_documents_read ON loan_documents;
CREATE POLICY loan_documents_read ON loan_documents
  FOR SELECT TO authenticated
  USING (
    loan_id IN (SELECT auth_own_loan_ids())
    OR auth_role() IN ('head_manager','employee')
  );

-- Co-maker documents: lender sees docs of co-makers on own loans;
-- HM/Employee all. Mirrors co_makers_read.
DROP POLICY IF EXISTS co_maker_documents_read ON co_maker_documents;
CREATE POLICY co_maker_documents_read ON co_maker_documents
  FOR SELECT TO authenticated
  USING (
    co_maker_id IN (
      SELECT lcm.co_maker_id
      FROM loan_co_makers lcm
      WHERE lcm.loan_id IN (SELECT auth_own_loan_ids())
    )
    OR auth_role() IN ('head_manager','employee')
  );

-- Payment reversals: HM/Employee all; lender sees reversals of payments
-- on own loans (same resolution shape as payments_read).
DROP POLICY IF EXISTS payment_reversals_read ON payment_reversals;
CREATE POLICY payment_reversals_read ON payment_reversals
  FOR SELECT TO authenticated
  USING (
    auth_role() IN ('head_manager','employee')
    OR EXISTS (
      SELECT 1
      FROM payments p
      JOIN loan_schedules ls ON ls.id = p.loan_schedule_id
      JOIN loans l ON l.id = ls.loan_id
      WHERE p.id = payment_reversals.payment_id
        AND l.lender_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM payments p
      JOIN collection_assignments ca ON ca.id = p.collection_assignment_id
      JOIN loan_schedules ls ON ls.id = ca.loan_schedule_id
      JOIN loans l ON l.id = ls.loan_id
      WHERE p.id = payment_reversals.payment_id
        AND l.lender_id = auth.uid()
    )
  );

-- Terms consent logs: users read their own consent history; HM all.
DROP POLICY IF EXISTS terms_consent_logs_read ON terms_consent_logs;
CREATE POLICY terms_consent_logs_read ON terms_consent_logs
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR auth_role() = 'head_manager'
  );

-- ─────────────────────────────────────────────────────────────────────
-- 3) collection_type: TEXT -> VARCHAR(20) for consistency.
--    text and varchar are binary-coercible: metadata-only change, no
--    table rewrite. Domain already enforced by
--    collection_assignments_collection_type_check (00033).
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE collection_assignments
  ALTER COLUMN collection_type TYPE VARCHAR(20);

COMMIT;
