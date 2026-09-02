-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00033_schema_audit_fixes.sql
-- Purpose   : Fixes for the gaps that survived verification of the
--             schema audit report. The report itself was mostly stale
--             (FKs, lookup-table enforcement, CHECKs and most indexes
--             already exist), but these items were genuinely missing:
--
--   1) Indexes backing RLS policies / hot joins that had none —
--      payments(loan_schedule_id), payments(collection_assignment_id),
--      collection_assignments(loan_schedule_id), disbursements(rider_id),
--      sms_logs(loan_schedule_id), xendit_logs(payment_id|disbursement_id),
--      in_office_applications(lender_id|loan_id), audit_logs(table,record),
--      otp_codes partial (drives trg_otp_invalidate_previous on every OTP),
--      account_upgrade_documents(reviewed_by).
--
--   2) Conditional status-completeness CHECKs the write path already
--      honors but the DB did not enforce:
--        loans        approved/active/completed/overdue -> approved_by
--        loans        rejected -> rejected_by + rejection_reason
--        loans        approved/active/completed/overdue -> term data
--        disbursements completed -> disbursed_at
--        collection_assignments completed -> completed_at
--        credit_investigations  completed -> completed_at
--        collection_assignments rider+assigned_by required unless the
--          row is a lender request ('requested'/'declined')
--        collection_assignments 'requested' rows must have requested_by
--        otp_codes.attempts >= 0, login_lockouts.failed_attempts >= 0
--        collection_assignments.collection_type IN ('rider','office')
--
--   All conditional CHECKs are added NOT VALID so existing rows can not
--   fail the migration; each is then VALIDATEd best-effort in its own
--   subtransaction (legacy violations surface as WARNINGs, not aborts).
--   Forward enforcement is active the moment the constraint exists.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) Missing indexes
-- ─────────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_payments_loan_schedule_id
  ON payments(loan_schedule_id);
CREATE INDEX IF NOT EXISTS idx_payments_collection_assignment_id
  ON payments(collection_assignment_id);

CREATE INDEX IF NOT EXISTS idx_coll_assign_loan_schedule_id
  ON collection_assignments(loan_schedule_id);
CREATE INDEX IF NOT EXISTS idx_disbursements_rider_id
  ON disbursements(rider_id);

CREATE INDEX IF NOT EXISTS idx_sms_logs_loan_schedule_id
  ON sms_logs(loan_schedule_id);

CREATE INDEX IF NOT EXISTS idx_xendit_logs_payment_id
  ON xendit_logs(payment_id);
CREATE INDEX IF NOT EXISTS idx_xendit_logs_disbursement_id
  ON xendit_logs(disbursement_id);

CREATE INDEX IF NOT EXISTS idx_in_office_lender_id
  ON in_office_applications(lender_id);

-- loan_id column does not exist on in_office_applications;
-- the FK is loans.in_office_application_id -> in_office_applications(id).
-- This index is intentionally skipped.

CREATE INDEX IF NOT EXISTS idx_audit_table_record
  ON audit_logs(table_name, record_id);

-- Drives fn_otp_invalidate_previous() which runs on EVERY otp insert.
CREATE INDEX IF NOT EXISTS idx_otp_phone_unused
  ON otp_codes(phone_number) WHERE used = FALSE;

CREATE INDEX IF NOT EXISTS idx_account_upgrade_docs_reviewed_by
  ON account_upgrade_documents(reviewed_by);

-- ─────────────────────────────────────────────────────────────────────
-- 2) Data repairs so VALIDATE can pass
-- ─────────────────────────────────────────────────────────────────────

-- Term data backfill (idempotent re-run of 00017): derive from schedule.
UPDATE loans l
SET term_periods       = s.cnt,
    installment_amount = s.first_amount
FROM (
  SELECT ls.loan_id,
         COUNT(*)                                                     AS cnt,
         (ARRAY_AGG(ls.amount_due ORDER BY ls.installment_number))[1] AS first_amount
  FROM loan_schedules ls
  GROUP BY ls.loan_id
) s
WHERE l.id = s.loan_id
  AND (l.term_periods IS NULL OR l.installment_amount IS NULL);

-- Completed disbursements missing their timestamp (e.g. rows completed by
-- the webhook before it started writing disbursed_at): use last update.
UPDATE disbursements
SET disbursed_at = COALESCE(disbursed_at, updated_at)
WHERE status = 'completed'
  AND disbursed_at IS NULL;

UPDATE collection_assignments
SET completed_at = COALESCE(completed_at, updated_at)
WHERE status = 'completed'
  AND completed_at IS NULL;

UPDATE credit_investigations
SET completed_at = COALESCE(completed_at, updated_at)
WHERE status = 'completed'
  AND completed_at IS NULL;

-- ─────────────────────────────────────────────────────────────────────
-- 3) Conditional integrity constraints (NOT VALID; validated below).
--    Idempotent: some of these may already exist on the remote (the
--    project has a history of hand-applying fixes in the SQL editor),
--    so each add is guarded by a pg_constraint existence check.
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION _add_check_if_missing(
  p_table TEXT, p_constraint TEXT, p_definition TEXT
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = p_constraint
      AND conrelid = format('%I.%I', 'public', p_table)::regclass
  ) THEN
    EXECUTE format(
      'ALTER TABLE %I ADD CONSTRAINT %I CHECK (%s) NOT VALID',
      p_table, p_constraint, p_definition
    );
  END IF;
END;
$$;

SELECT _add_check_if_missing(
  'loans', 'loans_approved_requires_approver',
  'status NOT IN (''approved'',''active'',''completed'',''overdue'') OR approved_by IS NOT NULL'
);

SELECT _add_check_if_missing(
  'loans', 'loans_rejected_requires_rejector',
  'status <> ''rejected'' OR (rejected_by IS NOT NULL AND rejection_reason IS NOT NULL)'
);

SELECT _add_check_if_missing(
  'loans', 'loans_post_approval_requires_term_data',
  'status NOT IN (''approved'',''active'',''completed'',''overdue'') OR (term_periods IS NOT NULL AND installment_amount IS NOT NULL)'
);

SELECT _add_check_if_missing(
  'disbursements', 'disbursements_completed_requires_disbursed_at',
  'status <> ''completed'' OR disbursed_at IS NOT NULL'
);

SELECT _add_check_if_missing(
  'collection_assignments', 'collection_assignments_completed_requires_completed_at',
  'status <> ''completed'' OR completed_at IS NOT NULL'
);

SELECT _add_check_if_missing(
  'credit_investigations', 'ci_completed_requires_completed_at',
  'status <> ''completed'' OR completed_at IS NOT NULL'
);

-- Rider-less rows are only legitimate while a lender request has not been
-- picked up ('requested') or was turned down before assignment ('declined').
SELECT _add_check_if_missing(
  'collection_assignments', 'collection_assignments_rider_required_unless_unassigned_request',
  'status IN (''requested'',''declined'') OR (rider_id IS NOT NULL AND assigned_by IS NOT NULL)'
);

SELECT _add_check_if_missing(
  'collection_assignments', 'collection_assignments_request_requires_requester',
  'status <> ''requested'' OR requested_by IS NOT NULL'
);

SELECT _add_check_if_missing('otp_codes', 'otp_codes_attempts_check', 'attempts >= 0');

SELECT _add_check_if_missing(
  'login_lockouts', 'login_lockouts_failed_attempts_check', 'failed_attempts >= 0'
);

SELECT _add_check_if_missing(
  'collection_assignments', 'collection_assignments_collection_type_check',
  'collection_type IN (''rider'',''office'')'
);

DROP FUNCTION _add_check_if_missing(TEXT, TEXT, TEXT);

-- ─────────────────────────────────────────────────────────────────────
-- 4) Best-effort VALIDATE — legacy violations warn instead of aborting
-- ─────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT table_name, constraint_name
    FROM (VALUES
      ('loans',                  'loans_approved_requires_approver'),
      ('loans',                  'loans_rejected_requires_rejector'),
      ('loans',                  'loans_post_approval_requires_term_data'),
      ('disbursements',          'disbursements_completed_requires_disbursed_at'),
      ('collection_assignments', 'collection_assignments_completed_requires_completed_at'),
      ('credit_investigations',  'ci_completed_requires_completed_at'),
      ('collection_assignments', 'collection_assignments_rider_required_unless_unassigned_request'),
      ('collection_assignments', 'collection_assignments_request_requires_requester')
    ) AS v(table_name, constraint_name)
  LOOP
    BEGIN
      EXECUTE format('ALTER TABLE %I VALIDATE CONSTRAINT %I',
                     r.table_name, r.constraint_name);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'Constraint %.% NOT validated (legacy rows violate it; enforcement still applies to new writes): %',
                    r.table_name, r.constraint_name, SQLERRM;
    END;
  END LOOP;
END $$;

COMMIT;
