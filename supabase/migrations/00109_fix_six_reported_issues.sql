-- =====================================================================
-- Migration: 00109_fix_six_reported_issues.sql
-- Purpose  : Fix/clarify the 6 issues from the Tagalog 10-point report
--            (Aug 2026) + standardize UUID defaults.
--
--   🔴 1) Circular FK loans <-> in_office_applications — VERIFIED FIXED.
--        00001_tables.sql:628-729 already breaks the cycle:
--          loans.in_office_application_id is plain UUID (no inline FK)
--          in_office_applications is created second (00001:710)
--          ALTER TABLE loans ADD CONSTRAINT fk_loans_in_office ... is run
--          AFTER both tables exist (00001:728). No execution error.
--        00099/00105 also DROP COLUMN in_office_applications.loan_id to keep
--        the relationship single-direction. This migration RE-ENSURES the FK
--        and drops any stray reverse FK if it reappears (e.g. manual add).
--        Fresh `supabase db reset` replay of 00001 alone succeeds — verified
--        by the ordering above.
--
--   🔴 2) lender_profiles naming as borrower — CLARIFY, non-breaking.
--        `lender` = borrower/client (role description in 00004:17 says
--        'Borrower who applies for loans'). Renaming the table to
--        borrower_profiles would touch ~100 app + edge files and break
--        realtime subscriptions. Instead: add COMMENT ON TABLE/COLUMN,
--        and a backward-compatible VIEW `borrower_profiles` + alias indexes.
--        A full rename script is included as commented block for v2.
--
--   🟠 3) account_upgrade_documents.status FK to account_upgrade_statuses
--        mixes account-level codes (not_submitted, submitted) with
--        document-level review (pending, verified, rejected). Create
--        normalized `document_review_statuses` and repoint the FK so
--        3NF domain is correct. Existing rows (pending/verified/rejected)
--        already satisfy the new lookup; any stray not_submitted/submitted
--        is migrated to pending before FK validate.
--
--   🟠 4) rider_locations.rider_id UNIQUE => one current location — DOCUMENT
--        + OPTIONAL history. Current design is intentional for realtime
--        tracking (location-manage upserts one row per rider). If you need
--        trail auditing, this migration creates `rider_location_history`
--        (1:N) and an archive trigger so every upsert is historized without
--        breaking the current-location read path.
--
--   🟠 5) payments.loan_schedule_id nullable — KEEP NULLABLE + CHECK.
--        Business case: office/gcash payments link via loan_schedule_id;
--        rider face-to-face links via collection_assignment_id. CHECK
--        payments_context_check already guarantees at least one link
--        (00108 deduped). Column stays nullable; strict NOT NULL mode is
--        left as commented ALTER for operators who want it.
--
--   🟠 6) loans.installment_amount vs loan_schedules.amount_due — DOCUMENT.
--        Not a bug: loans.installment_amount = agreed standard installment
--        (snapshot at approval, from 00017 term backfill); loan_schedules.
--        amount_due = per-installment actual due (may diverge with rounding/
--        penalty adjustments). Views v_loan_financials / v_loan_schedules are
--        source of truth for outstanding.
--
--   ⚠️ 10) UUID defaults mix gen_random_uuid() vs uuid_generate_v4() —
--        STANDARDIZE on gen_random_uuid() (pgcrypto, no uuid-ossp needed).
--        ALTER every id DEFAULT uuid_generate_v4() -> gen_random_uuid().
--
--   Idempotent: safe to re-run.
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

-- Ensure pgcrypto for gen_random_uuid() and uuid-ossp for legacy fallback
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─────────────────────────────────────────────────────────────────
-- 1) Circular FK — re-ensure canonical direction, remove reverse
-- ─────────────────────────────────────────────────────────────────
-- Drop stray reverse FK/column if someone re-added it manually.
ALTER TABLE public.in_office_applications DROP COLUMN IF EXISTS loan_id;

-- Drop stray FK that points in_office_applications -> loans (circular)
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT conname FROM pg_constraint
    WHERE conrelid='public.in_office_applications'::regclass
      AND contype='f'
      AND confrelid='public.loans'::regclass
  LOOP
    EXECUTE format('ALTER TABLE public.in_office_applications DROP CONSTRAINT %I', r.conname);
    RAISE NOTICE 'Dropped circular FK in_office_applications.% — was pointing to loans', r.conname;
  END LOOP;
END $$;

-- Ensure canonical FK loans.in_office_application_id -> in_office_applications(id)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname='fk_loans_in_office' AND conrelid='public.loans'::regclass
  ) THEN
    -- Orphan check: in_office_application_id values must exist in parent
    -- before FK can be added. Nulls are allowed (nullable column).
    IF EXISTS (
      SELECT 1 FROM public.loans l
      LEFT JOIN public.in_office_applications a ON a.id = l.in_office_application_id
      WHERE l.in_office_application_id IS NOT NULL AND a.id IS NULL
    ) THEN
      RAISE WARNING 'loans has orphan in_office_application_id — adding FK NOT VALID';
      ALTER TABLE public.loans
        ADD CONSTRAINT fk_loans_in_office FOREIGN KEY (in_office_application_id)
        REFERENCES public.in_office_applications(id) NOT VALID;
    ELSE
      ALTER TABLE public.loans
        ADD CONSTRAINT fk_loans_in_office FOREIGN KEY (in_office_application_id)
        REFERENCES public.in_office_applications(id);
    END IF;
    RAISE NOTICE 'Added FK fk_loans_in_office (loans -> in_office_applications)';
  ELSE
    -- Try to validate if it was NOT VALID before
    BEGIN
      ALTER TABLE public.loans VALIDATE CONSTRAINT fk_loans_in_office;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'fk_loans_in_office not validated (orphans): %', SQLERRM;
    END;
  END IF;
END $$;

COMMENT ON CONSTRAINT fk_loans_in_office ON public.loans IS
  'Canonical direction: loans.in_office_application_id -> in_office_applications(id). Reverse lookup: SELECT * FROM loans WHERE in_office_application_id = $app_id. Cycle broken by defining column without inline FK (00001:632) and adding FK AFTER both tables (00001:728). in_office_applications.loan_id was dropped (00099/00105).';

-- ─────────────────────────────────────────────────────────────────
-- 2) lender_profiles naming — clarify borrower semantics
-- ─────────────────────────────────────────────────────────────────
COMMENT ON TABLE public.lender_profiles IS
  'Borrower/client profile (1:1 child of users.id). The role/table is named lender for historical reasons but SEMANTICALLY means BORROWER — the person who borrows and repays. See roles.description: ''Borrower who applies for loans''. For readability, use the alias VIEW public.borrower_profiles. Chain: loans.lender_id -> lender_profiles.id -> users.id.';
COMMENT ON COLUMN public.lender_profiles.id IS 'PK = users.id (1:1). This is the borrower user id.';
COMMENT ON COLUMN public.lender_profiles.account_upgrade_status IS 'FK -> account_upgrade_statuses.code (not_submitted, pending, submitted, verified, rejected). Controls loan eligibility.';
COMMENT ON COLUMN public.loans.lender_id IS 'Borrower (client) who owns the loan. FK -> lender_profiles.id (which is 1:1 -> users.id). Despite the name lender, this is the BORROWER.';
COMMENT ON COLUMN public.in_office_applications.lender_id IS 'Borrower (lender_profiles.id) for in-office wizard. Nullable because wizard may start before borrower record is linked; created_by is the staff who opened it.';
COMMENT ON COLUMN public.emergency_contacts.lender_id IS 'Borrower (lender_profiles.id) this emergency contact belongs to.';
COMMENT ON COLUMN public.account_upgrade_documents.lender_id IS 'Borrower (lender_profiles.id) who uploaded the document.';

-- Backward-compatible alias VIEW: SELECT * FROM borrower_profiles == lender_profiles
CREATE OR REPLACE VIEW public.borrower_profiles AS
  SELECT * FROM public.lender_profiles;
ALTER VIEW public.borrower_profiles SET (security_invoker = true);
COMMENT ON VIEW public.borrower_profiles IS 'Alias VIEW for lender_profiles — semantically ''borrower_profiles''. Use this name in new code/docs for clarity; underlying table remains lender_profiles for backward compat. Writes go to lender_profiles; this VIEW is read-only alias.';
GRANT SELECT ON public.borrower_profiles TO anon, authenticated, service_role;

-- Also expose a convenience VIEW for role lookup (lender role == borrower role)
CREATE OR REPLACE VIEW public.borrower_role AS
  SELECT * FROM public.roles WHERE name = 'lender';
ALTER VIEW public.borrower_role SET (security_invoker = true);
COMMENT ON VIEW public.borrower_role IS 'Convenience alias: SELECT * FROM borrower_role returns the lender row (name=lender) which semantically means borrower.';
GRANT SELECT ON public.borrower_role TO anon, authenticated, service_role;

-- OPTIONAL FULL RENAME (destructive, for v2 — uncomment only in a maintenance window):
-- -- 1) Rename table + indexes + FKs + RLS policies + views
-- -- ALTER TABLE public.lender_profiles RENAME TO borrower_profiles;
-- -- ALTER INDEX lender_profiles_pkey RENAME TO borrower_profiles_pkey;
-- -- ALTER INDEX idx_lender_account_upgrade_status RENAME TO idx_borrower_account_upgrade_status;
-- -- -- Rename every lender_id column to borrower_id (requires FK drops/re-adds):
-- -- ALTER TABLE public.loans RENAME COLUMN lender_id TO borrower_id;
-- -- ALTER TABLE public.in_office_applications RENAME COLUMN lender_id TO borrower_id;
-- -- ALTER TABLE public.emergency_contacts RENAME COLUMN lender_id TO borrower_id;
-- -- ALTER TABLE public.account_upgrade_documents RENAME COLUMN lender_id TO borrower_id;
-- -- -- Update Role seed: UPDATE public.roles SET name='borrower' WHERE name='lender';
-- -- -- Then recreate FKs, RLS policies, functions (auth_own_loan_ids, etc.), and edge function env.
-- -- -- Keep alias: CREATE VIEW public.lender_profiles AS SELECT * FROM public.borrower_profiles;

-- ─────────────────────────────────────────────────────────────────
-- 3) account_upgrade_documents.status — normalize to document_review_statuses
-- ─────────────────────────────────────────────────────────────────
-- Create normalized lookup for document review decisions (distinct from
-- account_upgrade_statuses which governs the lender account lifecycle).
CREATE TABLE IF NOT EXISTS public.document_review_statuses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

ALTER TABLE public.document_review_statuses ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS document_review_statuses_read ON public.document_review_statuses;
CREATE POLICY document_review_statuses_read ON public.document_review_statuses
  FOR SELECT TO anon, authenticated USING (true);
GRANT SELECT ON public.document_review_statuses TO anon, authenticated;
GRANT ALL  ON public.document_review_statuses TO service_role;

-- set_updated_at trigger for new lookup
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_document_review_statuses_updated_at') THEN
    CREATE TRIGGER trg_document_review_statuses_updated_at
      BEFORE UPDATE ON public.document_review_statuses FOR EACH ROW EXECUTE FUNCTION set_updated_at();
  END IF;
END $$;

-- Seed canonical document review statuses (subset intentionally smaller than account_upgrade_statuses)
INSERT INTO public.document_review_statuses (code, label, sort_order, description) VALUES
  ('pending',  'Pending',  1, 'Document uploaded, awaiting staff review'),
  ('verified', 'Verified', 2, 'Document approved by staff'),
  ('rejected', 'Rejected', 3, 'Document rejected — see rejection_notes')
ON CONFLICT (code) DO NOTHING;

-- Ensure any account_upgrade_documents rows with account-level codes are mapped to document-level
-- (not_submitted/submitted should never appear on a document row; map them to pending)
UPDATE public.account_upgrade_documents
SET status = 'pending'
WHERE status IN ('not_submitted','submitted');

-- Ensure the new lookup has any stray status value before FK validate (defensive)
INSERT INTO public.document_review_statuses (code, label, sort_order)
SELECT DISTINCT status, initcap(status), 99
FROM public.account_upgrade_documents
WHERE status IS NOT NULL
  AND status NOT IN (SELECT code FROM public.document_review_statuses)
ON CONFLICT (code) DO NOTHING;

-- Add NEW FK account_upgrade_documents.status -> document_review_statuses(code)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
    WHERE c.conrelid='public.account_upgrade_documents'::regclass
      AND c.contype='f' AND a.attname='status'
      AND c.confrelid='public.document_review_statuses'::regclass
  ) THEN
    ALTER TABLE public.account_upgrade_documents
      ADD CONSTRAINT fk_aud_document_review_status
      FOREIGN KEY (status) REFERENCES public.document_review_statuses(code) NOT VALID;
    BEGIN
      ALTER TABLE public.account_upgrade_documents VALIDATE CONSTRAINT fk_aud_document_review_status;
      RAISE NOTICE 'Validated FK fk_aud_document_review_status (documents -> document_review_statuses)';
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'fk_aud_document_review_status NOT VALID (orphan status): %', SQLERRM;
    END;
  ELSE
    RAISE NOTICE 'FK account_upgrade_documents.status -> document_review_statuses(code) already exists';
  END IF;
END $$;

-- Drop OLD FK to account_upgrade_statuses now that new FK is the source of truth.
DO $$
DECLARE r RECORD;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname='fk_aud_document_review_status' AND conrelid='public.account_upgrade_documents'::regclass) THEN
    FOR r IN
      SELECT c.conname AS conname
      FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
      WHERE c.conrelid='public.account_upgrade_documents'::regclass
        AND c.contype='f'
        AND a.attname='status'
        AND c.confrelid='public.account_upgrade_statuses'::regclass
    LOOP
      BEGIN
        EXECUTE format('ALTER TABLE public.account_upgrade_documents DROP CONSTRAINT %I', r.conname);
        RAISE NOTICE 'Dropped old FK % (documents.status -> account_upgrade_statuses)', r.conname;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Failed to drop old FK %: %', r.conname, SQLERRM;
      END;
    END LOOP;
  END IF;
END $$;

-- Additional safety: attempt to drop known old names if they still exist (idempotent)
ALTER TABLE public.account_upgrade_documents DROP CONSTRAINT IF EXISTS account_upgrade_documents_status_fkey;
ALTER TABLE public.account_upgrade_documents DROP CONSTRAINT IF EXISTS fk_aud_status;

COMMENT ON TABLE public.document_review_statuses IS 'Normalized lookup for per-document review decisions (pending, verified, rejected). Distinct from account_upgrade_statuses which governs the lender account lifecycle (not_submitted..rejected). Added in 00109 to fix 🟠 #3 3NF concern.';
COMMENT ON COLUMN public.account_upgrade_documents.status IS 'FK -> document_review_statuses.code (pending, verified, rejected). Previously FK -> account_upgrade_statuses.code; migrated in 00109 for domain separation. Checked also by kyc-view handler which writes verified/rejected.';
COMMENT ON CONSTRAINT fk_aud_document_review_status ON public.account_upgrade_documents IS 'Domain FK: document review state vs account upgrade lifecycle. See document_review_statuses (pending, verified, rejected).';

-- ─────────────────────────────────────────────────────────────────
-- 4) rider_locations — document + history table + archive trigger
-- ─────────────────────────────────────────────────────────────────
COMMENT ON TABLE public.rider_locations IS
  'Current/latest location per rider (1 row per rider, UNIQUE(rider_id)). Optimized for realtime tracking: location-manage upserts here and lenders subscribe via Realtime. For location history/audit, see rider_location_history (created in 00109). If you need N location rows, query the history table.';
COMMENT ON COLUMN public.rider_locations.rider_id IS 'One current location per rider — UNIQUE ensures single latest GPS fix. History is in rider_location_history.';
COMMENT ON COLUMN public.rider_locations.updated_at IS 'Timestamp of latest GPS fix. Updated on every upsert from mobile.';

-- History table (1:N) for auditing / trail reconstruction. Not on the hot read path.
CREATE TABLE IF NOT EXISTS public.rider_location_history (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id    UUID NOT NULL REFERENCES public.rider_profiles(id) ON DELETE CASCADE,
  latitude    DECIMAL(10,8) NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude   DECIMAL(11,8) NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  accuracy    DECIMAL(8,2),
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rider_location_history_rider_id ON public.rider_location_history(rider_id);
CREATE INDEX IF NOT EXISTS idx_rider_location_history_recorded_at ON public.rider_location_history(recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_rider_location_history_rider_recorded ON public.rider_location_history(rider_id, recorded_at DESC);

ALTER TABLE public.rider_location_history ENABLE ROW LEVEL SECURITY;
-- No direct client write for anon; authenticated SELECT via RLS policy below.
-- Service_role (location-manage) writes.
REVOKE ALL ON TABLE public.rider_location_history FROM anon, authenticated;
GRANT SELECT ON public.rider_location_history TO authenticated;
GRANT ALL ON public.rider_location_history TO service_role;
-- Keep SELECT for authenticated via policy (same as rider_locations_read logic)
DROP POLICY IF EXISTS rider_location_history_read ON public.rider_location_history;
CREATE POLICY rider_location_history_read ON public.rider_location_history
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'lender'
      AND public.can_view_rider_location(rider_id)
    )
  );
COMMENT ON POLICY rider_location_history_read ON public.rider_location_history IS
  'Mirrors rider_locations_read (00107): head_manager/employee full, rider self, lender via can_view_rider_location(rider_id) (active collection/CI/disbursement).';

-- Archive trigger: every upsert to rider_locations logs a copy to history.
CREATE OR REPLACE FUNCTION public.fn_rider_locations_archive_history()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  INSERT INTO public.rider_location_history (rider_id, latitude, longitude, accuracy, recorded_at)
  VALUES (NEW.rider_id, NEW.latitude, NEW.longitude, NEW.accuracy, COALESCE(NEW.updated_at, NOW()));
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_rider_locations_archive ON public.rider_locations;
CREATE TRIGGER trg_rider_locations_archive
  AFTER INSERT OR UPDATE ON public.rider_locations
  FOR EACH ROW EXECUTE FUNCTION public.fn_rider_locations_archive_history();
COMMENT ON FUNCTION public.fn_rider_locations_archive_history() IS 'Archive every rider_locations upsert into rider_location_history for trail/audit. Hot path stays on rider_locations (1 row/rider); history is for analytics.';

-- Optional retention helper (call via cron): keep last 30 days or last N per rider
CREATE OR REPLACE FUNCTION public.cleanup_rider_location_history(p_retention_days int DEFAULT 30)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_deleted integer;
BEGIN
  DELETE FROM public.rider_location_history
  WHERE recorded_at < NOW() - (p_retention_days || ' days')::interval;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;
COMMENT ON FUNCTION public.cleanup_rider_location_history(int) IS 'Retention: deletes rider_location_history older than p_retention_days (default 30). Schedule via pg_cron or edge.';

-- ─────────────────────────────────────────────────────────────────
-- 5) payments.loan_schedule_id nullable — re-ensure CHECK, document
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE v_cnt int;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM pg_constraint
  WHERE conrelid='public.payments'::regclass AND contype='c'
    AND pg_get_constraintdef(oid) ILIKE '%loan_schedule_id%IS NOT NULL%OR%collection_assignment_id%IS NOT NULL%';
  IF v_cnt = 0 THEN
    ALTER TABLE public.payments
      ADD CONSTRAINT payments_context_check CHECK (loan_schedule_id IS NOT NULL OR collection_assignment_id IS NOT NULL) NOT VALID;
    BEGIN
      ALTER TABLE public.payments VALIDATE CONSTRAINT payments_context_check;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'payments_context_check NOT VALID (orphan payments): %', SQLERRM;
    END;
  ELSIF v_cnt > 1 THEN
    -- Dedup already handled in 00108; keep payments_context_check
    IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payments_must_have_link' AND conrelid='public.payments'::regclass) THEN
      ALTER TABLE public.payments DROP CONSTRAINT payments_must_have_link;
    END IF;
  END IF;
END $$;

COMMENT ON COLUMN public.payments.loan_schedule_id IS
  'Nullable by design (see 🟠 #5): office/gcash payments link here directly; rider face-to-face links via collection_assignment_id (which itself -> loan_schedules.id). CHECK payments_context_check guarantees at least one is NOT NULL. For strict mode (every payment must have direct schedule_id), run: ALTER TABLE public.payments ALTER COLUMN loan_schedule_id SET NOT NULL; after backfilling: UPDATE payments SET loan_schedule_id = (SELECT loan_schedule_id FROM collection_assignments WHERE id=collection_assignment_id) WHERE loan_schedule_id IS NULL.';
COMMENT ON COLUMN public.payments.collection_assignment_id IS
  'Alternative link for rider collections. Resolves to schedule via collection_assignments.loan_schedule_id. CHECK ensures loan_schedule_id OR collection_assignment_id is set.';
COMMENT ON CONSTRAINT payments_context_check ON public.payments IS
  'Ensures payment is never orphaned: at least one of loan_schedule_id or collection_assignment_id must be set. loan_schedule_id stays nullable to allow collection path (🟠 #5 documented in 00109).';


-- ─────────────────────────────────────────────────────────────────
-- 6) loans.installment_amount vs loan_schedules.amount_due — document
-- ─────────────────────────────────────────────────────────────────
COMMENT ON COLUMN public.loans.installment_amount IS
  'Agreed standard installment at approval time (snapshot, DECIMAL). Derived from principal_amount * (1+interest_rate/100) / term_periods and backfilled from loan_schedules (00105:308). Stays constant for audit; per-installment actual may diverge in loan_schedules.amount_due (rounding/penalty). Source of truth for outstanding is views v_loan_financials / v_loan_schedules, not this column alone.';
COMMENT ON COLUMN public.loans.term_periods IS
  'Number of installments derived from term_days + payment_frequency. Backfilled in 00105 from COUNT(loan_schedules). Used with installment_amount to display agreement.';
COMMENT ON COLUMN public.loans.principal_amount IS 'Original loan principal (3000..500000). total_payable = principal * (1+interest_rate/100) (see v_loan_financials).';
COMMENT ON COLUMN public.loan_schedules.amount_due IS
  'Actual amount due for THIS installment (installment_number). Usually equals loans.installment_amount but may differ per row for rounding/fee adjustments. payments.amount is checked against this per schedule via v_loan_schedules.amount_paid.';

-- ─────────────────────────────────────────────────────────────────
-- 10) UUID defaults — standardize on gen_random_uuid()
-- ─────────────────────────────────────────────────────────────────
-- Helper: set DEFAULT gen_random_uuid() where it is still uuid_generate_v4()
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT c.table_name, c.column_name
    FROM information_schema.columns c
    WHERE c.table_schema='public'
      AND c.column_default ILIKE '%uuid_generate_v4()%'
  LOOP
    BEGIN
      EXECUTE format('ALTER TABLE public.%I ALTER COLUMN %I SET DEFAULT gen_random_uuid()', r.table_name, r.column_name);
      RAISE NOTICE 'Standardized %.% DEFAULT -> gen_random_uuid()', r.table_name, r.column_name;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Failed to standardize %.%: %', r.table_name, r.column_name, SQLERRM;
    END;
  END LOOP;
END $$;

-- Keep uuid-ossp extension for backward compat but document preference
COMMENT ON EXTENSION "uuid-ossp" IS 'Retained for backward compat (uuid_generate_v4). New code should use gen_random_uuid() from pgcrypto (00109 standardized).';
COMMENT ON EXTENSION "pgcrypto" IS 'Preferred UUID source: gen_random_uuid() (00109).';

COMMIT;
