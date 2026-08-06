-- /supabase/migrations/00017_fix_rls_leaks.sql
-- Fix RLS data-leak policies so authenticated users can only read
-- their own records (or records scoped to their assignments/role).
--
-- NOTE: cross-table subqueries inside RLS policies on loans/credit_investigations/
-- collection_assignments cause "infinite recursion detected in policy" because the
-- policies reference each other (loans_read -> collection_assignments_read -> loans).
-- SECURITY DEFINER helpers run as the owner and bypass RLS, breaking the cycle.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper: loan ids the current user owns (is the lender on)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION auth_own_loan_ids()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT id FROM loans WHERE lender_id = auth.uid()
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper: loan ids a rider is assigned to (CI or collection)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rider_assigned_loan_ids()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT loan_id FROM credit_investigations WHERE rider_id = auth.uid()
  UNION
  SELECT loan_id FROM collection_assignments WHERE rider_id = auth.uid()
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper: lender (user) ids a rider is assigned to work with (via CI or collection)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rider_assigned_lender_ids()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT l.lender_id
  FROM credit_investigations ci
  JOIN loans l ON l.id = ci.loan_id
  WHERE ci.rider_id = auth.uid()
  UNION
  SELECT l.lender_id
  FROM collection_assignments ca
  JOIN loans l ON l.id = ca.loan_id
  WHERE ca.rider_id = auth.uid()
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- LOANS — lender reads own; HM/Employee all; Rider reads assigned loans
-- (replaces policy from 00002 to use the cycle-breaking helper)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "loans_read" ON loans;

CREATE POLICY "loans_read" ON loans
  FOR SELECT TO authenticated
  USING (
    lender_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'rider'
      AND id IN (SELECT rider_assigned_loan_ids())
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- LOAN SCHEDULES — lender reads own loan schedules; HM/Employee all;
-- Rider reads schedules of loans they are assigned to (CI or collections)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "loan_schedules_read" ON loan_schedules;

CREATE POLICY "loan_schedules_read" ON loan_schedules
  FOR SELECT TO authenticated
  USING (
    loan_id IN (SELECT auth_own_loan_ids())
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'rider'
      AND loan_id IN (SELECT rider_assigned_loan_ids())
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- CO MAKERS — lender reads co-makers of own loans; HM/Employee all;
-- rider cannot read co-makers
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "co_makers_read" ON co_makers;

CREATE POLICY "co_makers_read" ON co_makers
  FOR SELECT TO authenticated
  USING (
    loan_id IN (SELECT auth_own_loan_ids())
    OR auth_role() IN ('head_manager','employee')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- CI DOCUMENTS — rider reads docs of their own CI only; HM/Employee all
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "ci_documents_read" ON ci_documents;

CREATE POLICY "ci_documents_read" ON ci_documents
  FOR SELECT TO authenticated
  USING (
    ci_id IN (
      SELECT id FROM credit_investigations WHERE rider_id = auth.uid()
    )
    OR auth_role() IN ('head_manager','employee')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- ADDRESSES — rider reads addresses only of lenders they are assigned to
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "addresses_read" ON addresses;

CREATE POLICY "addresses_read" ON addresses
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'rider'
      AND user_id IN (SELECT rider_assigned_lender_ids())
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- EMERGENCY CONTACTS — rider reads contacts only of lenders they are assigned to
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "emergency_contacts_read" ON emergency_contacts;

CREATE POLICY "emergency_contacts_read" ON emergency_contacts
  FOR SELECT TO authenticated
  USING (
    lender_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'rider'
      AND lender_id IN (SELECT rider_assigned_lender_ids())
    )
  );

COMMIT;
