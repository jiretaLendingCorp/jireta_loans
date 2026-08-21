-- ============================================================
-- Migration: 00099_schema_fixes.sql
-- Fixes all remaining schema issues identified in v3 review
-- ============================================================

-- ============================================================
-- FIX #1: CIRCULAR FK — Drop loan_id from in_office_applications
-- loans.in_office_application_id is the canonical reference.
-- Query reverse direction: SELECT * FROM loans WHERE in_office_application_id = $app_id
-- ============================================================
ALTER TABLE public.in_office_applications
  DROP COLUMN IF EXISTS loan_id;


-- ============================================================
-- FIX #2: PAYMENTS — Enforce at least one FK must be set
-- Prevents orphaned payment records with no loan linkage.
-- ============================================================
ALTER TABLE public.payments
  ADD CONSTRAINT payments_must_have_link
  CHECK (
    loan_schedule_id IS NOT NULL
    OR collection_assignment_id IS NOT NULL
  );


-- ============================================================
-- FIX #3: UNIQUE constraint — role_permissions
-- Prevents the same permission being granted to a role twice.
-- ============================================================
ALTER TABLE public.role_permissions
  ADD CONSTRAINT uq_role_permission
  UNIQUE (role_id, permission_id);


-- ============================================================
-- FIX #4: UNIQUE constraint — loan_co_makers
-- Prevents the same co-maker being linked to a loan twice.
-- ============================================================
ALTER TABLE public.loan_co_makers
  ADD CONSTRAINT uq_loan_co_maker
  UNIQUE (loan_id, co_maker_id);


-- ============================================================
-- FIX #5: NOTIFICATIONS — Add UPDATE policy for mark-as-read
-- Users must be able to set is_read = true and read_at on
-- their own notifications. Restrict updatable columns via
-- the Edge Function; this policy gates the row-level access.
-- ============================================================
CREATE POLICY notifications_update_own
  ON public.notifications
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());


-- ============================================================
-- FIX #6: WIZARD STEP — Range check constraint
-- Adjust upper bound (7) to match your actual wizard steps.
-- ============================================================
ALTER TABLE public.in_office_applications
  ADD CONSTRAINT chk_wizard_step
  CHECK (wizard_step BETWEEN 1 AND 7);
