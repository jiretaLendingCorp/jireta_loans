-- /supabase/migrations/00031_loan_disbursement_preference.sql
-- Stores the borrower's disbursement preference captured at application time
-- (e.g. preferred method + GCash number) so the release modal can prefill it.
--
-- 3NF note: the preference is a distinct fact from the actual disbursement
-- event, so it lives in its own 1:1 table (loan_disbursement_preferences)
-- instead of snapshot columns duplicated on `loans` or mixed into
-- `disbursements`. loans.disbursement_account was never part of the
-- normalized schema (00021 dropped disbursement_* snapshots), but guard
-- against a partially-applied column from earlier drafts.

BEGIN;

ALTER TABLE loans DROP COLUMN IF EXISTS disbursement_account;

CREATE TABLE IF NOT EXISTS loan_disbursement_preferences (
  loan_id                 UUID PRIMARY KEY REFERENCES loans(id) ON DELETE CASCADE,
  method                  VARCHAR(20) CHECK (method IN ('gcash','office_cash','rider_delivery')),
  account                 VARCHAR(255),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_loan_disb_prefs_loan_id ON loan_disbursement_preferences(loan_id);

CREATE TRIGGER trg_loan_disb_prefs_updated_at
  BEFORE UPDATE ON loan_disbursement_preferences
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE loan_disbursement_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "loan_disbursement_preferences_read" ON loan_disbursement_preferences
  FOR SELECT TO authenticated
  USING (
    loan_id IN (SELECT auth_own_loan_ids())
    OR auth_role() IN ('head_manager','employee')
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON loan_disbursement_preferences TO service_role;

COMMIT;