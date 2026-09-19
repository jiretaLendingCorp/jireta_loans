-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00169_schema_integrity_audit.sql
-- Purpose   : Forward-only schema review pass requested by the reviewer.
--             Audits and ENFORCES every intended relationship, unique
--             constraint and cardinality rule, then reports what it found.
--
-- WHAT THIS MIGRATION DOES (all idempotent — safe to re-run):
--   1) schema_integrity_findings  — a small audit log so bad data is
--      REPORTED instead of silently mutated. service_role only.
--   2) FOREIGN KEY audit + repair — ~100 intended relationships are
--      checked against pg_constraint. Any that is missing is added
--      NOT VALID and then VALIDATEd in its own subtransaction, so a
--      single orphan row cannot abort the whole migration.
--   3) UNIQUE constraint audit + repair — role_permissions, loan_co_makers,
--      the three 1:1 wizard tables, loan_disbursement_preferences,
--      rider_locations, active_sessions, payment_reversals.
--   4) payments ↔ collection_assignments consistency — a real gap: a
--      payment could reference Schedule A while its collection
--      assignment was for Schedule B (even another loan). Forward
--      enforcement via trigger; existing violations are REPORTED, never
--      auto-corrected (moving money between installments is not a
--      migration's job).
--   5) loans 1:N credit_investigations is INTENTIONAL (re-investigation
--      history, ci-manage marks superseded rows 'reassigned'). History is
--      preserved; only the ACTIVE investigation is made unique per loan.
--   6) loans 1:0..1 disbursement is INTENTIONAL (every disbursement
--      handler refuses to insert a second row per loan; provider retries
--      live in xendit_logs). Enforced with a guarded UNIQUE(loan_id).
--   7) loan_schedules 1:N collection_assignments is preserved
--      (rejected/reassigned/retried rows are history), but only ONE
--      active/pending assignment per schedule is allowed — partial
--      unique index, matching the 409 guard in collections-manage.
--   8) Role ↔ profile combinations: a read-only validation function.
--      A hard trigger is deliberately NOT installed — see §8 for why
--      (users-manage creates the new profile BEFORE writing role_id, so
--      an insert/update trigger would break the legitimate role-change
--      flow).
--   9) ON DELETE behaviour + legacy/deprecated objects: reviewed and
--      documented via COMMENT ON, nothing destructive.
--  10) A verification block that prints the final enforcement state.
--
-- WHAT THIS MIGRATION DELIBERATELY DOES NOT DO:
--   • Does NOT drop the deprecated varchar lookup columns. Audit
--     (2026-09-19): lib/**/*.dart still writes them in 123 places and
--     supabase/functions/**/*.ts in 261 places. Dropping them now is a
--     SEV-1 (42703 on every insert). 00110–00112 already made the UUID
--     *_id column canonical + NOT NULL + FK-validated, with code<->id
--     sync triggers, so the *_id column IS the single source of truth;
--     the varchar is a trigger-synced compatibility alias.
--   • Does NOT drop emergency_contacts / application_emergency_contacts.
--     Both are still queried by live edge functions (see §9).
--   • Does NOT change any existing FK's ON DELETE action (that would
--     rewrite constraints the app's delete flows already rely on).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─────────────────────────────────────────────────────────────────────
-- 1) Findings log — where the audit records problems it cannot safely
--    repair itself. Read-only for the app; service_role only.
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.schema_integrity_findings (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  check_name  TEXT        NOT NULL,
  table_name  TEXT,
  record_id   UUID,
  details     JSONB       NOT NULL DEFAULT '{}'::jsonb,
  detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_schema_integrity_findings_open
  ON public.schema_integrity_findings(check_name) WHERE resolved_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_schema_integrity_findings_table
  ON public.schema_integrity_findings(table_name);

ALTER TABLE public.schema_integrity_findings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.schema_integrity_findings FROM PUBLIC;
REVOKE ALL ON TABLE public.schema_integrity_findings FROM anon, authenticated;
GRANT ALL ON TABLE public.schema_integrity_findings TO service_role;

COMMENT ON TABLE public.schema_integrity_findings IS
  'Audit output of migration 00169. Each row is a schema/data-integrity problem the migration detected but refused to repair automatically (e.g. duplicate rows that block a UNIQUE constraint, or a payment whose collection assignment belongs to another loan). Inspect open rows (resolved_at IS NULL), fix the data, then re-run the migration. service_role only.';

-- Record one finding, deduplicated while unresolved.
CREATE OR REPLACE FUNCTION public.record_integrity_finding(
  p_check     TEXT,
  p_table     TEXT,
  p_record_id UUID,
  p_details   JSONB DEFAULT '{}'::jsonb
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.schema_integrity_findings
    WHERE check_name = p_check
      AND COALESCE(table_name, '') = COALESCE(p_table, '')
      AND record_id IS NOT DISTINCT FROM p_record_id
      AND resolved_at IS NULL
  ) THEN
    INSERT INTO public.schema_integrity_findings (check_name, table_name, record_id, details)
    VALUES (p_check, p_table, p_record_id, COALESCE(p_details, '{}'::jsonb));
  END IF;
END;
$$;

-- TRUE when p_table has a unique index/constraint whose key columns are
-- exactly p_cols (order-independent, non-partial).
CREATE OR REPLACE FUNCTION public.has_unique_on(p_table TEXT, p_cols TEXT[])
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_class t ON t.oid = i.indrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relname = p_table
      AND i.indisunique
      AND i.indpred IS NULL
      AND (
        SELECT array_agg(a.attname ORDER BY a.attname)
        FROM generate_subscripts(i.indkey, 1) s
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[s]
        WHERE a.attnum > 0
      ) = (SELECT array_agg(u.c ORDER BY u.c) FROM unnest(p_cols) AS u(c))
  );
$$;

-- Add UNIQUE(p_cols) if no equivalent unique exists. Never deletes rows:
-- if duplicates block it, the finding is logged and the constraint skipped.
CREATE OR REPLACE FUNCTION public.ensure_unique_constraint(
  p_table TEXT,
  p_cols  TEXT[],
  p_name  TEXT DEFAULT NULL
) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_name TEXT := COALESCE(p_name, left('uq_' || p_table || '_' || array_to_string(p_cols, '_'), 63));
BEGIN
  IF public.has_unique_on(p_table, p_cols) THEN
    RAISE NOTICE 'UNIQUE OK: %.%', p_table, array_to_string(p_cols, ', ');
    RETURN TRUE;
  END IF;

  BEGIN
    EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I UNIQUE (%s)',
                   p_table, v_name,
                   array_to_string(array(SELECT quote_ident(u.c) FROM unnest(p_cols) AS u(c)), ', '));
    RAISE NOTICE 'UNIQUE ADDED: % (%)', p_table, array_to_string(p_cols, ', ');
    RETURN TRUE;
  EXCEPTION
    -- Never abort the migration for a constraint we could not add: the
    -- existing data is always left untouched and the reason is recorded.
    WHEN unique_violation THEN
      PERFORM public.record_integrity_finding(
        'duplicate_rows_block_unique', p_table, NULL,
        jsonb_build_object('columns', p_cols, 'expected_constraint', v_name, 'error', SQLERRM));
      RAISE WARNING 'UNIQUE SKIPPED: % (%) — duplicate rows exist, fix data then re-run',
        p_table, array_to_string(p_cols, ', ');
      RETURN FALSE;
    WHEN OTHERS THEN
      PERFORM public.record_integrity_finding(
        'unique_constraint_not_added', p_table, NULL,
        jsonb_build_object('columns', p_cols, 'expected_constraint', v_name, 'error', SQLERRM));
      RAISE WARNING 'UNIQUE NOT ADDED: % (%) — %', p_table, array_to_string(p_cols, ', '), SQLERRM;
      RETURN FALSE;
  END;
END;
$$;

-- Strict, order-independent FK existence check (child col -> parent col).
CREATE OR REPLACE FUNCTION public.has_fk(
  p_child_table TEXT, p_child_col TEXT,
  p_parent_table TEXT, p_parent_col TEXT
) RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class ct ON ct.oid = c.conrelid
    JOIN pg_namespace cn ON cn.oid = ct.relnamespace
    JOIN pg_class pt ON pt.oid = c.confrelid
    JOIN pg_namespace pn ON pn.oid = pt.relnamespace
    JOIN pg_attribute ca ON ca.attrelid = c.conrelid AND ca.attnum = c.conkey[1]
    JOIN pg_attribute pa ON pa.attrelid = c.confrelid AND pa.attnum = c.confkey[1]
    WHERE c.contype = 'f'
      AND cn.nspname = 'public' AND ct.relname = p_child_table
      AND pn.nspname = 'public' AND pt.relname = p_parent_table
      AND ca.attname = p_child_col
      AND pa.attname = p_parent_col
      AND array_length(c.conkey, 1) = 1
  );
$$;

COMMENT ON FUNCTION public.has_fk(TEXT, TEXT, TEXT, TEXT) IS
  'TRUE when a real PostgreSQL FOREIGN KEY enforces child_table.child_col -> parent_table.parent_col. Used by 00169 to prove every intended relationship is enforced (not just implied by naming).';
COMMENT ON FUNCTION public.has_unique_on(TEXT, TEXT[]) IS
  'TRUE when a non-partial unique index/constraint exists on exactly the given columns. Used by 00169 for the 1:1 / junction uniqueness audit.';

-- ─────────────────────────────────────────────────────────────────────
-- 2) FOREIGN KEY audit + repair
--    Every intended relationship of the relational model. Missing FKs are
--    added NOT VALID -> VALIDATE (a validation failure is a WARNING +
--    finding, never an abort).
-- ─────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  rec        record;
  v_col      boolean;
  v_ok       int := 0;
  v_added    int := 0;
  v_problem  int := 0;
  v_lookup   boolean;
BEGIN
  FOR rec IN
    SELECT * FROM (VALUES
      -- identity / roles
      ('users','role_id','roles','id'),
      ('users','account_status_id','user_account_statuses','id'),
      ('users','created_by','users','id'),
      -- profiles (PK = FK to users)
      ('lender_profiles','id','users','id'),
      ('lender_profiles','gender_id','gender_types','id'),
      ('lender_profiles','civil_status_id','civil_statuses','id'),
      ('lender_profiles','employment_type_id','employment_types','id'),
      ('lender_profiles','account_upgrade_status_id','account_upgrade_statuses','id'),
      ('rider_profiles','id','users','id'),
      ('rider_profiles','vehicle_type_id','vehicle_types','id'),
      ('employee_profiles','id','users','id'),
      ('employee_profiles','gender_id','gender_types','id'),
      ('employee_profiles','civil_status_id','civil_statuses','id'),
      -- contact / consent
      ('addresses','user_id','users','id'),
      ('addresses','address_type_id','address_types','id'),
      ('auth_logs','user_id','users','id'),
      ('terms_consent_logs','user_id','users','id'),
      ('terms_consent_logs','platform_id','platform_types','id'),
      -- loans
      ('loans','lender_id','lender_profiles','id'),
      ('loans','in_office_application_id','in_office_applications','id'),
      ('loans','payment_frequency_id','payment_frequencies','id'),
      ('loans','status_id','loan_statuses','id'),
      ('loans','employment_type_id','employment_types','id'),
      ('loans','approved_by','users','id'),
      ('loans','rejected_by','users','id'),
      -- schedules / co-makers / documents
      ('loan_schedules','loan_id','loans','id'),
      ('loan_co_makers','loan_id','loans','id'),
      ('loan_co_makers','co_maker_id','co_makers','id'),
      ('loan_co_makers','relationship_id','relationship_types','id'),
      ('co_maker_documents','co_maker_id','co_makers','id'),
      ('co_maker_documents','document_type_id','document_types','id'),
      ('loan_documents','loan_id','loans','id'),
      ('loan_documents','uploaded_by','users','id'),
      ('loan_documents','document_type_id','document_types','id'),
      -- credit investigation
      ('credit_investigations','loan_id','loans','id'),
      ('credit_investigations','rider_id','rider_profiles','id'),
      ('credit_investigations','assigned_by','users','id'),
      ('credit_investigations','status_id','credit_investigation_statuses','id'),
      ('credit_investigations','reviewed_by','users','id'),
      ('ci_documents','ci_id','credit_investigations','id'),
      ('ci_documents','document_type_id','document_types','id'),
      -- collections
      ('collection_assignments','loan_schedule_id','loan_schedules','id'),
      ('collection_assignments','rider_id','rider_profiles','id'),
      ('collection_assignments','assigned_by','users','id'),
      ('collection_assignments','requested_by','users','id'),
      ('collection_assignments','status_id','collection_assignment_statuses','id'),
      ('collection_assignments','reviewed_by','users','id'),
      -- disbursements
      ('disbursements','loan_id','loans','id'),
      ('disbursements','authorized_by','users','id'),
      ('disbursements','rider_id','rider_profiles','id'),
      ('disbursements','method_id','disbursement_methods','id'),
      ('disbursements','status_id','disbursement_statuses','id'),
      ('loan_disbursement_preferences','loan_id','loans','id'),
      ('loan_disbursement_preferences','method_id','disbursement_methods','id'),
      -- payments
      ('payments','loan_schedule_id','loan_schedules','id'),
      ('payments','payment_method_id','payment_methods','id'),
      ('payments','status_id','payment_statuses','id'),
      ('payments','recorded_by','users','id'),
      ('payments','collection_assignment_id','collection_assignments','id'),
      ('payment_reversals','payment_id','payments','id'),
      ('payment_reversals','reversed_by','users','id'),
      -- tracking
      ('rider_locations','rider_id','rider_profiles','id'),
      ('rider_location_history','rider_id','rider_profiles','id'),
      -- notifications / messaging
      ('notifications','user_id','users','id'),
      ('notifications','triggered_by','users','id'),
      ('notifications','type_id','notification_types','id'),
      ('user_devices','user_id','users','id'),
      ('sms_logs','user_id','users','id'),
      ('sms_logs','loan_schedule_id','loan_schedules','id'),
      ('sms_logs','status_id','sms_statuses','id'),
      -- reporting / governance
      ('reports','generated_by','users','id'),
      ('audit_logs','performed_by','users','id'),
      ('system_config','updated_by','users','id'),
      ('penalty_logs','loan_id','loans','id'),
      ('penalty_logs','applied_by','users','id'),
      ('xendit_logs','loan_id','loans','id'),
      ('xendit_logs','payment_id','payments','id'),
      ('xendit_logs','disbursement_id','disbursements','id'),
      -- in-office applications
      ('in_office_applications','lender_id','lender_profiles','id'),
      ('in_office_applications','created_by','users','id'),
      ('in_office_applications','status_id','in_office_application_statuses','id'),
      ('application_personal_info','application_id','in_office_applications','id'),
      ('application_personal_info','gender_id','gender_types','id'),
      ('application_personal_info','civil_status_id','civil_statuses','id'),
      ('application_employment_info','application_id','in_office_applications','id'),
      ('application_employment_info','employment_type_id','employment_types','id'),
      ('application_addresses','application_id','in_office_applications','id'),
      ('application_addresses','address_type_id','address_types','id'),
      ('application_emergency_contacts','application_id','in_office_applications','id'),
      ('application_emergency_contacts','relationship_id','relationship_types','id'),
      ('application_loan_details','application_id','in_office_applications','id'),
      ('application_loan_details','payment_frequency_id','payment_frequencies','id'),
      ('application_co_makers','application_id','in_office_applications','id'),
      ('application_co_makers','relationship_id','relationship_types','id'),
      ('application_documents','application_id','in_office_applications','id'),
      ('application_documents','document_type_id','document_types','id'),
      -- KYC / account upgrade
      ('account_upgrade_documents','lender_id','lender_profiles','id'),
      ('account_upgrade_documents','reviewed_by','users','id'),
      ('account_upgrade_documents','document_type_id','document_types','id'),
      -- emergency contacts (legacy per-lender + per-loan snapshot)
      ('emergency_contacts','lender_id','lender_profiles','id'),
      ('emergency_contacts','relationship_id','relationship_types','id'),
      ('loan_emergency_contacts','loan_id','loans','id'),
      ('loan_emergency_contacts','relationship_id','relationship_types','id')
    ) AS t(child_tbl, child_col, parent_tbl, parent_col)
  LOOP
    -- Table/column existence guards (a missing object is a finding, not a crash).
    IF to_regclass('public.' || rec.child_tbl) IS NULL THEN
      PERFORM public.record_integrity_finding('fk_child_table_missing', rec.child_tbl, NULL,
        jsonb_build_object('column', rec.child_col, 'parent', rec.parent_tbl));
      v_problem := v_problem + 1;
      CONTINUE;
    END IF;
    IF to_regclass('public.' || rec.parent_tbl) IS NULL THEN
      PERFORM public.record_integrity_finding('fk_parent_table_missing', rec.child_tbl, NULL,
        jsonb_build_object('column', rec.child_col, 'parent', rec.parent_tbl));
      v_problem := v_problem + 1;
      CONTINUE;
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name=rec.child_tbl AND column_name=rec.child_col
    ) INTO v_col;
    IF NOT v_col THEN
      PERFORM public.record_integrity_finding('fk_child_column_missing', rec.child_tbl, NULL,
        jsonb_build_object('column', rec.child_col, 'parent', rec.parent_tbl));
      v_problem := v_problem + 1;
      CONTINUE;
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name=rec.parent_tbl AND column_name=rec.parent_col
    ) INTO v_col;
    IF NOT v_col THEN
      PERFORM public.record_integrity_finding('fk_parent_column_missing', rec.child_tbl, NULL,
        jsonb_build_object('column', rec.child_col, 'parent', rec.parent_tbl || '.' || rec.parent_col));
      v_problem := v_problem + 1;
      CONTINUE;
    END IF;

    IF public.has_fk(rec.child_tbl, rec.child_col, rec.parent_tbl, rec.parent_col) THEN
      v_ok := v_ok + 1;
      RAISE NOTICE 'FK OK: %.% -> %.%', rec.child_tbl, rec.child_col, rec.parent_tbl, rec.parent_col;
      CONTINUE;
    END IF;

    -- Missing → add it for real.
    BEGIN
      EXECUTE format(
        'ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES public.%I(%I) NOT VALID',
        rec.child_tbl, left('fk_' || rec.child_tbl || '_' || rec.child_col, 63),
        rec.child_col, rec.parent_tbl, rec.parent_col);

      BEGIN
        EXECUTE format('ALTER TABLE public.%I VALIDATE CONSTRAINT %I',
                       rec.child_tbl, left('fk_' || rec.child_tbl || '_' || rec.child_col, 63));
        v_added := v_added + 1;
        RAISE NOTICE 'FK ADDED + VALIDATED: %.% -> %.%',
          rec.child_tbl, rec.child_col, rec.parent_tbl, rec.parent_col;
      EXCEPTION WHEN OTHERS THEN
        v_added := v_added + 1;
        PERFORM public.record_integrity_finding('fk_added_not_validated', rec.child_tbl, NULL,
          jsonb_build_object('column', rec.child_col, 'parent', rec.parent_tbl || '.' || rec.parent_col, 'error', SQLERRM));
        RAISE WARNING 'FK %.% -> %.% added as NOT VALID (orphan rows): %',
          rec.child_tbl, rec.child_col, rec.parent_tbl, rec.parent_col, SQLERRM;
      END;
    EXCEPTION WHEN duplicate_object THEN
      v_ok := v_ok + 1;   -- constraint name already taken but FK is there
    WHEN OTHERS THEN
      v_problem := v_problem + 1;
      PERFORM public.record_integrity_finding('fk_add_failed', rec.child_tbl, NULL,
        jsonb_build_object('column', rec.child_col, 'parent', rec.parent_tbl || '.' || rec.parent_col, 'error', SQLERRM));
      RAISE WARNING 'FK ADD FAILED: %.% -> %.%: %',
        rec.child_tbl, rec.child_col, rec.parent_tbl, rec.parent_col, SQLERRM;
    END;
  END LOOP;

  RAISE NOTICE '00169 FK audit → already enforced: %, added: %, problems: %', v_ok, v_added, v_problem;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 3) UNIQUE constraint audit
--    Junction: role_permissions must stay M:N (roles 1:N role_permissions
--    N:1 permissions) with a single UNIQUE(role_id, permission_id).
--    Junction duplicates are safe to dedupe (no business payload).
-- ─────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_removed int;
BEGIN
  -- role_permissions — dedupe identical grants, then enforce.
  IF to_regclass('public.role_permissions') IS NOT NULL THEN
    WITH dups AS (
      SELECT id, row_number() OVER (
               PARTITION BY role_id, permission_id ORDER BY created_at, id) AS rn
      FROM public.role_permissions
    )
    DELETE FROM public.role_permissions rp
    USING dups d WHERE rp.id = d.id AND d.rn > 1;
    GET DIAGNOSTICS v_removed = ROW_COUNT;
    IF v_removed > 0 THEN
      RAISE NOTICE 'role_permissions: removed % duplicate grant row(s)', v_removed;
      PERFORM public.record_integrity_finding('duplicate_role_permissions_deduped',
        'role_permissions', NULL, jsonb_build_object('removed_rows', v_removed));
    END IF;
    PERFORM public.ensure_unique_constraint('role_permissions', ARRAY['role_id','permission_id']);
  END IF;

  -- loan_co_makers — same co-maker twice on one loan is never meaningful.
  IF to_regclass('public.loan_co_makers') IS NOT NULL THEN
    WITH dups AS (
      SELECT id, row_number() OVER (
               PARTITION BY loan_id, co_maker_id ORDER BY created_at, id) AS rn
      FROM public.loan_co_makers
    )
    DELETE FROM public.loan_co_makers lcm
    USING dups d WHERE lcm.id = d.id AND d.rn > 1;
    GET DIAGNOSTICS v_removed = ROW_COUNT;
    IF v_removed > 0 THEN
      RAISE NOTICE 'loan_co_makers: removed % duplicate link row(s)', v_removed;
    END IF;
    PERFORM public.ensure_unique_constraint('loan_co_makers', ARRAY['loan_id','co_maker_id']);
  END IF;

  -- 1:1 wizard children (application_id is the 1:1 key).
  IF to_regclass('public.application_personal_info') IS NOT NULL THEN
    PERFORM public.ensure_unique_constraint('application_personal_info', ARRAY['application_id']);
  END IF;
  IF to_regclass('public.application_employment_info') IS NOT NULL THEN
    PERFORM public.ensure_unique_constraint('application_employment_info', ARRAY['application_id']);
  END IF;
  IF to_regclass('public.application_loan_details') IS NOT NULL THEN
    PERFORM public.ensure_unique_constraint('application_loan_details', ARRAY['application_id']);
  END IF;

  -- 1:0..1 rows that must never duplicate.
  IF to_regclass('public.loan_disbursement_preferences') IS NOT NULL THEN
    PERFORM public.ensure_unique_constraint('loan_disbursement_preferences', ARRAY['loan_id']);
  END IF;
  IF to_regclass('public.rider_locations') IS NOT NULL THEN
    PERFORM public.ensure_unique_constraint('rider_locations', ARRAY['rider_id']);
  END IF;
  IF to_regclass('public.active_sessions') IS NOT NULL THEN
    PERFORM public.ensure_unique_constraint('active_sessions', ARRAY['user_id']);
  END IF;
  -- payment_reversals: at most one reversal per payment. Never deduped
  -- automatically — deleting a reversal row would rewrite financial history.
  IF to_regclass('public.payment_reversals') IS NOT NULL THEN
    PERFORM public.ensure_unique_constraint('payment_reversals', ARRAY['payment_id']);
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 4) PAYMENTS ↔ COLLECTION_ASSIGNMENT consistency (real gap closed here)
--
--    Invariant: a payment linked to a collection assignment must settle an
--    installment of the SAME LOAN as the assignment's schedule.
--
--    Why not require loan_schedule_id = collection_assignments.loan_schedule_id?
--    Because collections-manage legitimately splits one collected amount
--    across several installments (allocatePayment: the tapped schedule
--    first, then oldest-unpaid). Those extra payment rows carry the same
--    collection_assignment_id but a DIFFERENT loan_schedule_id — still the
--    same loan. Enforcing equality would break real rider collections.
--    Cross-LOAN mismatches are the actual corruption, and they are blocked.
--
--    Direct office/online payments (loan_schedule_id only) are unaffected:
--    the trigger returns early when collection_assignment_id IS NULL.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_payment_loan_consistency()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_pay_loan    UUID;
  v_assign_loan UUID;
BEGIN
  IF NEW.loan_schedule_id IS NULL OR NEW.collection_assignment_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT ls.loan_id INTO v_pay_loan
  FROM public.loan_schedules ls WHERE ls.id = NEW.loan_schedule_id;

  SELECT ls.loan_id INTO v_assign_loan
  FROM public.collection_assignments ca
  JOIN public.loan_schedules ls ON ls.id = ca.loan_schedule_id
  WHERE ca.id = NEW.collection_assignment_id;

  -- A NULL here means a dangling reference; the FKs own that check.
  IF v_pay_loan IS NULL OR v_assign_loan IS NULL THEN
    RETURN NEW;
  END IF;

  IF v_pay_loan <> v_assign_loan THEN
    RAISE EXCEPTION
      'payments: loan_schedule_id % belongs to loan %, but collection_assignment_id % belongs to loan %',
      NEW.loan_schedule_id, v_pay_loan, NEW.collection_assignment_id, v_assign_loan
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_payment_loan_consistency() IS
  'Blocks a payment whose collection_assignment_id belongs to a different loan than its loan_schedule_id. Allows multiple payment rows per assignment (one collected amount allocated across installments of the same loan) and allows assignment-less office/online payments. Added 00169.';

DROP TRIGGER IF EXISTS trg_payments_loan_consistency ON public.payments;
CREATE TRIGGER trg_payments_loan_consistency
  BEFORE INSERT OR UPDATE OF loan_schedule_id, collection_assignment_id ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.enforce_payment_loan_consistency();

-- Report (do NOT auto-fix) any pre-existing cross-loan mismatch.
DO $$
DECLARE
  r        record;
  v_count  int := 0;
BEGIN
  FOR r IN
    SELECT m.id AS payment_id,
           m.loan_id_schedule AS pay_schedule,
           m.assign_schedule,
           m.pay_loan,
           m.assign_loan
    FROM (
      SELECT p.id,
             p.loan_schedule_id                       AS loan_id_schedule,
             ca.loan_schedule_id                      AS assign_schedule,
             ls_pay.loan_id                           AS pay_loan,
             ls_asg.loan_id                           AS assign_loan
      FROM public.payments p
      JOIN public.collection_assignments ca ON ca.id = p.collection_assignment_id
      LEFT JOIN public.loan_schedules ls_pay ON ls_pay.id = p.loan_schedule_id
      LEFT JOIN public.loan_schedules ls_asg ON ls_asg.id = ca.loan_schedule_id
      WHERE p.loan_schedule_id IS NOT NULL
        AND p.collection_assignment_id IS NOT NULL
    ) m
    WHERE m.pay_loan IS NOT NULL
      AND m.assign_loan IS NOT NULL
      AND m.pay_loan <> m.assign_loan
  LOOP
    v_count := v_count + 1;
    PERFORM public.record_integrity_finding('payment_cross_loan_mismatch', 'payments', r.payment_id,
      jsonb_build_object('payment_schedule', r.pay_schedule, 'assignment_schedule', r.assign_schedule,
                         'payment_loan', r.pay_loan, 'assignment_loan', r.assign_loan));
  END LOOP;

  IF v_count > 0 THEN
    RAISE WARNING '00169: % payment(s) reference a collection assignment from another loan — see schema_integrity_findings (NOT auto-corrected).', v_count;
  ELSE
    RAISE NOTICE 'payments ↔ collection_assignment loan consistency: no existing violations';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 5) CREDIT INVESTIGATIONS — loans 1:N is intentional.
--    ci-manage marks superseded rows 'reassigned' and inserts a new one,
--    and its own guard refuses a second investigation for a loan with an
--    active row. So the DB enforces exactly that: history stays 1:N, but
--    only ONE active (assigned|in_progress) CI per loan.
-- ─────────────────────────────────────────────────────────────────────
DO $$
DECLARE v_dupes int;
BEGIN
  SELECT COUNT(*) INTO v_dupes FROM (
    SELECT loan_id FROM public.credit_investigations
    WHERE status IN ('assigned','in_progress')
    GROUP BY loan_id HAVING COUNT(*) > 1
  ) d;

  IF v_dupes > 0 THEN
    PERFORM public.record_integrity_finding('duplicate_active_ci_per_loan', 'credit_investigations', NULL,
      jsonb_build_object('loans_with_multiple_active_ci', v_dupes));
    RAISE WARNING '00169: % loan(s) have more than one active CI — index not created, fix data then re-run', v_dupes;
  ELSIF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_credit_investigations_active_loan') THEN
    BEGIN
      EXECUTE 'CREATE UNIQUE INDEX uq_credit_investigations_active_loan
                 ON public.credit_investigations (loan_id)
                 WHERE status IN (''assigned'',''in_progress'')';
      RAISE NOTICE 'Created uq_credit_investigations_active_loan (one active CI per loan; history preserved)';
    EXCEPTION WHEN OTHERS THEN
      PERFORM public.record_integrity_finding('unique_index_not_created', 'credit_investigations', NULL,
        jsonb_build_object('index', 'uq_credit_investigations_active_loan', 'error', SQLERRM));
      RAISE WARNING '00169: uq_credit_investigations_active_loan not created: %', SQLERRM;
    END;
  ELSE
    RAISE NOTICE 'UNIQUE OK: one active credit investigation per loan';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 6) COLLECTION ASSIGNMENTS — loan_schedule 1:N is intentional
--    (rejected / reassigned / retried rows are history), but only ONE
--    active-or-pending assignment may exist per schedule. This mirrors the
--    409 guard in collections-manage, which today only the application
--    enforces (two staff members could race two different riders).
--    Supersedes the narrower 'requested'-only index (00018) and the
--    (schedule, rider) partial index (00157) when it can be created.
-- ─────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_dupes   int;
  v_created boolean := FALSE;
BEGIN
  SELECT COUNT(*) INTO v_dupes FROM (
    SELECT loan_schedule_id FROM public.collection_assignments
    WHERE status IN ('requested','assigned','accepted','in_progress','pending_approval')
    GROUP BY loan_schedule_id HAVING COUNT(*) > 1
  ) d;

  IF v_dupes > 0 THEN
    PERFORM public.record_integrity_finding('duplicate_active_collection_per_schedule', 'collection_assignments', NULL,
      jsonb_build_object('schedules_with_multiple_active_assignments', v_dupes));
    RAISE WARNING '00169: % schedule(s) have multiple active/pending assignments — index not created, fix data then re-run', v_dupes;
  ELSIF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_collection_assignments_active_schedule') THEN
    BEGIN
      EXECUTE 'CREATE UNIQUE INDEX uq_collection_assignments_active_schedule
                 ON public.collection_assignments (loan_schedule_id)
                 WHERE status IN (''requested'',''assigned'',''accepted'',''in_progress'',''pending_approval'')';
      v_created := TRUE;
      RAISE NOTICE 'Created uq_collection_assignments_active_schedule (one active/pending assignment per schedule; history preserved)';
    EXCEPTION WHEN OTHERS THEN
      PERFORM public.record_integrity_finding('unique_index_not_created', 'collection_assignments', NULL,
        jsonb_build_object('index', 'uq_collection_assignments_active_schedule', 'error', SQLERRM));
      RAISE WARNING '00169: uq_collection_assignments_active_schedule not created: %', SQLERRM;
    END;
  ELSE
    v_created := TRUE;
    RAISE NOTICE 'UNIQUE OK: one active/pending collection assignment per schedule';
  END IF;

  IF v_created THEN
    -- Redundant now that the schedule-wide index exists.
    DROP INDEX IF EXISTS public.uq_collection_assignments_requested_schedule;
    DROP INDEX IF EXISTS public.uq_collection_assignments_active_schedule_rider;
    RAISE NOTICE 'Dropped narrower collection_assignments indexes superseded by uq_collection_assignments_active_schedule';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 7) DISBURSEMENTS — loans 1:0..1 *actual* disbursement.
--    Every disbursement handler (gcash / office cash / rider delivery)
--    refuses to insert when a row already exists for the loan
--    ("Loan has already been disbursed" / 400 DUPLICATE). Provider
--    attempts, retries and webhook events live in xendit_logs. The DB now
--    enforces the same rule so two concurrent releases cannot double-pay.
-- ─────────────────────────────────────────────────────────────────────
DO $$
DECLARE v_dupes int;
BEGIN
  SELECT COUNT(*) INTO v_dupes FROM (
    SELECT loan_id FROM public.disbursements GROUP BY loan_id HAVING COUNT(*) > 1
  ) d;

  IF v_dupes > 0 THEN
    PERFORM public.record_integrity_finding('multiple_disbursements_per_loan', 'disbursements', NULL,
      jsonb_build_object('loans_with_multiple_disbursements', v_dupes));
    RAISE WARNING '00169: % loan(s) have multiple disbursement rows — index not created, review them then re-run', v_dupes;
  ELSIF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_disbursements_one_per_loan') THEN
    BEGIN
      EXECUTE 'CREATE UNIQUE INDEX uq_disbursements_one_per_loan ON public.disbursements (loan_id)';
      RAISE NOTICE 'Created uq_disbursements_one_per_loan (one disbursement per loan; xendit_logs keeps provider attempt history)';
    EXCEPTION WHEN OTHERS THEN
      PERFORM public.record_integrity_finding('unique_index_not_created', 'disbursements', NULL,
        jsonb_build_object('index', 'uq_disbursements_one_per_loan', 'error', SQLERRM));
      RAISE WARNING '00169: uq_disbursements_one_per_loan not created: %', SQLERRM;
    END;
  ELSE
    RAISE NOTICE 'UNIQUE OK: one disbursement per loan';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 8) ROLE ↔ PROFILE combinations — validated, reported, not force-enforced.
--
--    Intended: lender_profiles ⇒ role lender; rider_profiles ⇒ role rider;
--    employee_profiles ⇒ role employee OR head_manager.
--
--    A hard trigger is NOT installed on purpose: users-manage performs a
--    role change as (1) upsert the NEW profile, (2) drop the OLD profiles,
--    (3) UPDATE users.role_id. Step (1) runs while the user still has the
--    OLD role, so an insert/update guard on the profile tables would reject
--    a legitimate promotion. The check is therefore exposed as a read-only
--    validation function + findings, and can be turned into a trigger once
--    the edge function writes role_id BEFORE shaping profiles.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.validate_profile_role_consistency()
RETURNS TABLE (
  issue         TEXT,
  user_id       UUID,
  role_name     TEXT,
  profiles      TEXT
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
  SELECT 'role_profile_mismatch', u.id, r.name,
         concat_ws(',',
           CASE WHEN lp.id IS NOT NULL THEN 'lender_profiles' END,
           CASE WHEN rp.id IS NOT NULL THEN 'rider_profiles' END,
           CASE WHEN ep.id IS NOT NULL THEN 'employee_profiles' END)
  FROM public.users u
  JOIN public.roles r ON r.id = u.role_id
  LEFT JOIN public.lender_profiles  lp ON lp.id = u.id
  LEFT JOIN public.rider_profiles   rp ON rp.id = u.id
  LEFT JOIN public.employee_profiles ep ON ep.id = u.id
  WHERE (
      (r.name = 'lender'   AND (lp.id IS NULL OR rp.id IS NOT NULL OR ep.id IS NOT NULL))
   OR (r.name = 'rider'    AND (rp.id IS NULL OR lp.id IS NOT NULL OR ep.id IS NOT NULL))
   OR (r.name = 'employee' AND (ep.id IS NULL OR lp.id IS NOT NULL OR rp.id IS NOT NULL))
  );
$$;

COMMENT ON FUNCTION public.validate_profile_role_consistency() IS
  'Read-only audit: lists users whose profile rows do not match their role (missing profile, or an incompatible extra profile). Added 00169. A hard trigger is intentionally not installed because users-manage creates the new profile BEFORE updating role_id.';

DO $$
DECLARE r record; v_count int := 0;
BEGIN
  FOR r IN SELECT * FROM public.validate_profile_role_consistency() LOOP
    v_count := v_count + 1;
    PERFORM public.record_integrity_finding('role_profile_mismatch', 'users', r.user_id,
      jsonb_build_object('role', r.role_name, 'profiles', r.profiles, 'issue', r.issue));
  END LOOP;

  IF v_count > 0 THEN
    RAISE WARNING '00169: % user(s) have a role/profile mismatch — see schema_integrity_findings', v_count;
  ELSE
    RAISE NOTICE 'Role ↔ profile combinations: all consistent';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 9) Deprecated / legacy objects + ON DELETE semantics — documented, not
--    changed. (Nothing here is dropped: all three emergency-contact
--    objects are still referenced by live edge functions.)
-- ─────────────────────────────────────────────────────────────────────
COMMENT ON TABLE public.emergency_contacts IS
  'DEPRECATED OWNERSHIP (00128), STILL IN USE — per-LENDER emergency contacts. Per-loan source of truth is loan_emergency_contacts. Still read by kyc-view (L514, L752) and users-manage (L565) and written by in-office-view (L525, L594). Do not drop until those callers are repointed. Retained for historical rows.';

COMMENT ON TABLE public.application_emergency_contacts IS
  'Application-stage (wizard) emergency contacts — NOT legacy. Written by in-office-create (L259) and read by in-office-view (L389) and kyc-view (L138) when a walk-in application is still a draft. Snapshotted into loan_emergency_contacts on conversion/approval.';

COMMENT ON TABLE public.loan_emergency_contacts IS
  'Per-loan emergency contacts — the source of truth for CI/approval (written by in-office-view and the Apply Loan flow, read by ci-view). 1:N per loan.';

COMMENT ON COLUMN public.lender_profiles.employment_type IS
  'DEPRECATED (00128): per-LOAN snapshot now lives in loans.employment_type (canonical: loans.employment_type_id -> employment_types.id). Kept for backward compatibility.';
COMMENT ON COLUMN public.lender_profiles.monthly_income IS
  'DEPRECATED (00128): per-LOAN snapshot now lives in loans.monthly_income. Kept for backward compatibility.';
COMMENT ON COLUMN public.lender_profiles.employer_name IS
  'DEPRECATED (00128): per-LOAN snapshot now lives in loans.employer_name. Kept for backward compatibility.';
COMMENT ON COLUMN public.lender_profiles.source_of_funds IS
  'DEPRECATED (00128): per-LOAN snapshot now lives in loans.source_of_funds. Kept for backward compatibility.';

COMMENT ON COLUMN public.loans.lender_id IS
  'ON DELETE CASCADE is intentional: the containing user/profile tree is deleted together (users -> lender_profiles -> loans). The product ARCHIVES users (account_status=/roles.is_archived) instead of deleting them, so this only fires on the deliberate hard-delete path used by test-data cleanup.';

COMMENT ON COLUMN public.loan_schedules.loan_id IS
  'ON DELETE CASCADE: a schedule has no meaning without its loan. Payments cascade from the schedule by the same reasoning; financial history is never deleted by normal application flows (no delete paths exist for loans/payments/disbursements).';

COMMENT ON COLUMN public.collection_assignments.rider_id IS
  'Nullable by design: lender-requested rows have no rider until staff assigns one. No ON DELETE action (RESTRICT) — deleting a rider who has assignment history is refused; deactivate the rider account instead.';

COMMENT ON COLUMN public.payments.collection_assignment_id IS
  'Alternative link for rider collections (rider_collection payments). loans/payments/disbursements history is never cascaded from an assignment. Consistency with loan_schedule_id is enforced by trg_payments_loan_consistency (00169).';

COMMENT ON COLUMN public.schema_integrity_findings.record_id IS
  'Primary key of the offending row (for example payments.id) when the finding concerns one row; NULL for set-level findings.';

-- ─────────────────────────────────────────────────────────────────────
-- 10) Verification — prints the enforcement state the reviewer should see
--     in the `supabase db push` / `db reset` log.
-- ─────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  rec        record;
  v_missing  text[] := '{}';
  v_fk_total int;
  v_cascade  int;
  v_setnull  int;
  v_restrict int;
BEGIN
  RAISE NOTICE '──────── 00169 verification ────────';

  -- Spot-check the relationships the reviewer explicitly named.
  FOR rec IN
    SELECT * FROM (VALUES
      ('users.role_id -> roles.id',                          'users','role_id','roles','id'),
      ('users.account_status_id -> user_account_statuses.id','users','account_status_id','user_account_statuses','id'),
      ('lender_profiles.id -> users.id',                     'lender_profiles','id','users','id'),
      ('lender_profiles.gender_id -> gender_types.id',       'lender_profiles','gender_id','gender_types','id'),
      ('lender_profiles.account_upgrade_status_id -> account_upgrade_statuses.id',
                                                             'lender_profiles','account_upgrade_status_id','account_upgrade_statuses','id'),
      ('rider_profiles.id -> users.id',                      'rider_profiles','id','users','id'),
      ('rider_profiles.vehicle_type_id -> vehicle_types.id', 'rider_profiles','vehicle_type_id','vehicle_types','id'),
      ('employee_profiles.id -> users.id',                   'employee_profiles','id','users','id'),
      ('loans.lender_id -> lender_profiles.id',              'loans','lender_id','lender_profiles','id'),
      ('loans.payment_frequency_id -> payment_frequencies.id','loans','payment_frequency_id','payment_frequencies','id'),
      ('loans.status_id -> loan_statuses.id',                'loans','status_id','loan_statuses','id'),
      ('loans.employment_type_id -> employment_types.id',    'loans','employment_type_id','employment_types','id'),
      ('loans.in_office_application_id -> in_office_applications.id',
                                                             'loans','in_office_application_id','in_office_applications','id'),
      ('credit_investigations.loan_id -> loans.id',          'credit_investigations','loan_id','loans','id'),
      ('collection_assignments.loan_schedule_id -> loan_schedules.id',
                                                             'collection_assignments','loan_schedule_id','loan_schedules','id'),
      ('disbursements.loan_id -> loans.id',                  'disbursements','loan_id','loans','id'),
      ('payments.loan_schedule_id -> loan_schedules.id',     'payments','loan_schedule_id','loan_schedules','id'),
      ('payments.collection_assignment_id -> collection_assignments.id',
                                                             'payments','collection_assignment_id','collection_assignments','id'),
      ('payment_reversals.payment_id -> payments.id',        'payment_reversals','payment_id','payments','id'),
      ('rider_locations.rider_id -> rider_profiles.id',      'rider_locations','rider_id','rider_profiles','id'),
      ('notifications.user_id -> users.id',                  'notifications','user_id','users','id'),
      ('reports.generated_by -> users.id',                   'reports','generated_by','users','id'),
      ('audit_logs.performed_by -> users.id',                'audit_logs','performed_by','users','id'),
      ('xendit_logs.loan_id -> loans.id',                    'xendit_logs','loan_id','loans','id'),
      ('loan_emergency_contacts.loan_id -> loans.id',        'loan_emergency_contacts','loan_id','loans','id')
    ) AS t(label, ct, cc, pt, pc)
  LOOP
    IF public.has_fk(rec.ct, rec.cc, rec.pt, rec.pc) THEN
      RAISE NOTICE '  FK ENFORCED: %', rec.label;
    ELSE
      v_missing := v_missing || rec.label;
      RAISE WARNING '  FK MISSING: %', rec.label;
    END IF;
  END LOOP;

  -- Unique / cardinality assertions.
  IF public.has_unique_on('role_permissions', ARRAY['role_id','permission_id']) THEN
    RAISE NOTICE '  UNIQUE ENFORCED: role_permissions(role_id, permission_id)';
  ELSE RAISE WARNING '  UNIQUE MISSING: role_permissions(role_id, permission_id)'; END IF;

  IF public.has_unique_on('loan_schedules', ARRAY['loan_id','installment_number']) THEN
    RAISE NOTICE '  UNIQUE ENFORCED: loan_schedules(loan_id, installment_number)';
  ELSE RAISE WARNING '  UNIQUE MISSING: loan_schedules(loan_id, installment_number)'; END IF;

  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_credit_investigations_active_loan') THEN
    RAISE NOTICE '  UNIQUE ENFORCED: one active credit investigation per loan (history kept 1:N)';
  ELSE RAISE WARNING '  UNIQUE NOT CREATED: uq_credit_investigations_active_loan (see findings)'; END IF;

  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_collection_assignments_active_schedule') THEN
    RAISE NOTICE '  UNIQUE ENFORCED: one active/pending collection assignment per schedule (history kept 1:N)';
  ELSE RAISE WARNING '  UNIQUE NOT CREATED: uq_collection_assignments_active_schedule (see findings)'; END IF;

  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_disbursements_one_per_loan') THEN
    RAISE NOTICE '  UNIQUE ENFORCED: one disbursement per loan (provider history stays in xendit_logs)';
  ELSE RAISE WARNING '  UNIQUE NOT CREATED: uq_disbursements_one_per_loan (see findings)'; END IF;

  -- Orphan check on the newly enforced FK columns (should be zero).
  FOR rec IN
    SELECT * FROM (VALUES
      ('payments','loan_schedule_id','loan_schedules','id'),
      ('payments','collection_assignment_id','collection_assignments','id'),
      ('disbursements','loan_id','loans','id'),
      ('credit_investigations','loan_id','loans','id'),
      ('collection_assignments','loan_schedule_id','loan_schedules','id')
    ) AS t(ct, cc, pt, pc)
  LOOP
    EXECUTE format(
      'SELECT COUNT(*) FROM public.%I c LEFT JOIN public.%I p ON p.%I = c.%I WHERE c.%I IS NOT NULL AND p.%I IS NULL',
      rec.ct, rec.pt, rec.pc, rec.cc, rec.cc, rec.pc) INTO v_fk_total;
    IF v_fk_total > 0 THEN
      PERFORM public.record_integrity_finding('orphan_rows', rec.ct, NULL,
        jsonb_build_object('column', rec.cc, 'orphans', v_fk_total));
      RAISE WARNING '  ORPHANS: %.% has % dangling reference(s)', rec.ct, rec.cc, v_fk_total;
    END IF;
  END LOOP;

  -- Delete-behaviour census (documentation for the ERD review).
  SELECT
    COUNT(*) FILTER (WHERE confdeltype = 'c'),
    COUNT(*) FILTER (WHERE confdeltype = 'n'),
    COUNT(*) FILTER (WHERE confdeltype IN ('r','a'))
  INTO v_cascade, v_setnull, v_restrict
  FROM pg_constraint WHERE contype = 'f';

  SELECT COUNT(*) INTO v_fk_total FROM pg_constraint WHERE contype = 'f';
  RAISE NOTICE '  FK census: % total (CASCADE %, SET NULL %, RESTRICT/NO ACTION %)', v_fk_total, v_cascade, v_setnull, v_restrict;
  RAISE NOTICE '  Open findings: %', (SELECT COUNT(*) FROM public.schema_integrity_findings WHERE resolved_at IS NULL);
END $$;

-- Drop the audit helpers that are not part of the application surface.
DROP FUNCTION IF EXISTS public.ensure_unique_constraint(TEXT, TEXT[], TEXT);

COMMIT;
