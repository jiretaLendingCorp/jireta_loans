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
CREATE INDEX IF NOT EXISTS idx_in_office_loan_id
  ON in_office_applications(loan_id);

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
-- 3) Conditional integrity constraints (NOT VALID; validated below)
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE loans ADD CONSTRAINT loans_approved_requires_approver
  CHECK (status NOT IN ('approved','active','completed','overdue')
         OR approved_by IS NOT NULL) NOT VALID;

ALTER TABLE loans ADD CONSTRAINT loans_rejected_requires_rejector
  CHECK (status <> 'rejected'
         OR (rejected_by IS NOT NULL AND rejection_reason IS NOT NULL)) NOT VALID;

ALTER TABLE loans ADD CONSTRAINT loans_post_approval_requires_term_data
  CHECK (status NOT IN ('approved','active','completed','overdue')
         OR (term_periods IS NOT NULL AND installment_amount IS NOT NULL)) NOT VALID;

ALTER TABLE disbursements ADD CONSTRAINT disbursements_completed_requires_disbursed_at
  CHECK (status <> 'completed' OR disbursed_at IS NOT NULL) NOT VALID;

ALTER TABLE collection_assignments
  ADD CONSTRAINT collection_assignments_completed_requires_completed_at
  CHECK (status <> 'completed' OR completed_at IS NOT NULL) NOT VALID;

ALTER TABLE credit_investigations ADD CONSTRAINT ci_completed_requires_completed_at
  CHECK (status <> 'completed' OR completed_at IS NOT NULL) NOT VALID;

-- Rider-less rows are only legitimate while a lender request has not been
-- picked up ('requested') or was turned down before assignment ('declined').
ALTER TABLE collection_assignments
  ADD CONSTRAINT collection_assignments_rider_required_unless_unassigned_request
  CHECK (status IN ('requested','declined')
         OR (rider_id IS NOT NULL AND assigned_by IS NOT NULL)) NOT VALID;

ALTER TABLE collection_assignments
  ADD CONSTRAINT collection_assignments_request_requires_requester
  CHECK (status <> 'requested' OR requested_by IS NOT NULL) NOT VALID;

ALTER TABLE otp_codes ADD CONSTRAINT otp_codes_attempts_check
  CHECK (attempts >= 0);

ALTER TABLE login_lockouts ADD CONSTRAINT login_lockouts_failed_attempts_check
  CHECK (failed_attempts >= 0);

ALTER TABLE collection_assignments ADD CONSTRAINT collection_assignments_collection_type_check
  CHECK (collection_type IN ('rider','office'));

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
