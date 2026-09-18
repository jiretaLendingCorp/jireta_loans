-- supabase/migrations/00168_remove_views_and_test_account.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Drop the redundant READ-ONLY VIEW layer that only duplicated real tables
--    (ERD / documentation helpers):
--      • v_users_canonical, v_lender_profiles_canonical, v_loans_canonical,
--        v_payments_canonical, v_disbursements_canonical  (canonical ERD views)
--      • v_loan_financials  (derived financials — no longer queried by any code)
--      • borrower_* alias views  (borrower_profiles, borrower_role,
--        borrower_loans, borrower_emergency_contacts,
--        borrower_account_upgrade_documents, borrower_in_office_applications)
--
--    NOT dropped — public.v_loan_schedules: the edge functions
--    (payments-manage, loans-view, collections-manage and
--    _shared/loan_financials.ts) read the payment schedule from it. Removing it
--    would break payments / loan details, so it stays until those callers are
--    refactored onto the base tables.
--
--    The matching CREATE VIEW / GRANT / COMMENT blocks were also removed from
--    the earlier migrations (00002, 00003, 00109, 00111, 00112, 00128), so a
--    fresh `db reset` no longer creates any of them. This migration only
--    cleans up databases where they were already applied.
--
-- 2) Delete the demo "Overdue Lender" test account seeded by the old
--    00139_seed_overdue_lender.sql (phone 09171234567,
--    email overdue.lender@jireta.temp, UUID d1a2b3c4-…-a1) together with every
--    row it created (loan, schedules, disbursement, penalty, address, profile,
--    auth user).
--
-- Idempotent: DROP VIEW IF EXISTS + targeted DELETEs (safe to re-run).
-- Every DELETE is guarded with to_regclass so a table that does not exist in a
-- given environment (schema drift, e.g. sms_logs) can never abort the cleanup.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- ── 1) Drop the redundant view layer ────────────────────────────────────────
DROP VIEW IF EXISTS public.v_users_canonical;
DROP VIEW IF EXISTS public.v_lender_profiles_canonical;
DROP VIEW IF EXISTS public.v_loans_canonical;
DROP VIEW IF EXISTS public.v_payments_canonical;
DROP VIEW IF EXISTS public.v_disbursements_canonical;
DROP VIEW IF EXISTS public.v_loan_financials;

DROP VIEW IF EXISTS public.borrower_profiles;
DROP VIEW IF EXISTS public.borrower_role;
DROP VIEW IF EXISTS public.borrower_loans;
DROP VIEW IF EXISTS public.borrower_emergency_contacts;
DROP VIEW IF EXISTS public.borrower_account_upgrade_documents;
DROP VIEW IF EXISTS public.borrower_in_office_applications;

-- ── 2) Delete the test account + everything it created ──────────────────────
DO $$
DECLARE
  v_user_id UUID := 'd1a2b3c4-0000-4000-8000-0000000000a1';
  v_loan_id UUID := 'd1a2b3c4-0000-4000-8000-0000000000a2';
  v_email   TEXT := 'overdue.lender@jireta.temp';
  r         record;
BEGIN
  -- Ordered deletes. Deleting the loan cascades the whole loan tree
  -- (loan_schedules -> payments, collection_assignments, disbursements,
  -- penalty_logs, credit_investigations, documents, emergency contacts,
  -- xendit logs, co-makers, disbursement preferences, ...). The two entries
  -- before it have no ON DELETE action and must be cleared first.
  FOR r IN
    SELECT * FROM (VALUES
      ('sms_logs',
       format('user_id = %L OR loan_schedule_id IN (SELECT id FROM public.loan_schedules WHERE loan_id = %L)', v_user_id, v_loan_id)),
      ('payment_reversals',
       format('payment_id IN (SELECT id FROM public.payments WHERE loan_schedule_id IN (SELECT id FROM public.loan_schedules WHERE loan_id = %L))', v_loan_id)),
      ('loans',
       format('id = %L', v_loan_id)),
      ('audit_logs',
       format('performed_by = %L', v_user_id)),
      ('reports',
       format('generated_by = %L', v_user_id)),
      ('notifications',
       format('user_id = %L OR triggered_by = %L', v_user_id, v_user_id)),
      ('in_office_applications',
       format('lender_id = %L', v_user_id)),
      ('lender_profiles',
       format('id = %L', v_user_id)),
      ('users',
       format('id = %L', v_user_id))
    ) AS t(tbl, cond)
  LOOP
    IF to_regclass('public.' || r.tbl) IS NOT NULL THEN
      EXECUTE format('DELETE FROM public.%I WHERE %s', r.tbl, r.cond);
    END IF;
  END LOOP;

  -- Account login row. Everything else that references users cascades.
  IF to_regclass('auth.users') IS NOT NULL THEN
    EXECUTE format('DELETE FROM auth.users WHERE id = %L OR email = %L', v_user_id, v_email);
  END IF;

  RAISE NOTICE 'Removed overdue-lender test account % and its loan %', v_user_id, v_loan_id;
END $$;

COMMIT;
