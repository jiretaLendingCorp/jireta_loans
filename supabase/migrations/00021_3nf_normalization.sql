-- /supabase/migrations/00021_3nf_normalization.sql
-- 3NF normalization pass:
--
-- 1) Drop snapshot columns on `lender_profiles` that duplicate the `blacklist`
--    and `addresses` tables (single source of truth for each fact).
-- 2) Drop snapshot columns on `loans` that duplicate `disbursements` and
--    `penalty_logs`, plus the derived `total_payable`/`outstanding_balance`.
-- 3) Drop derived columns on `loan_schedules` (`amount_paid`, `status`, `paid_at`)
--    — computable from `payments`.
-- 4) Drop the transitive-dependency columns `collection_assignments.loan_id`
--    and `payments.loan_id` (loan is reachable through `loan_schedules`), and
--    preserve the loan-delete cascade by moving it onto `loan_schedule_id`.
-- 5) Update RLS helper functions/policies that referenced the dropped columns.
-- 6) Expose the computed financials through read-only views
--    (`v_loan_financials`, `v_loan_schedules`) for direct SQL / reporting.
--
-- NOTE ON ORDERING: PostgreSQL refuses to drop a column while any object
-- (policy, SQL-language function, index, constraint) still depends on it.
-- The RLS policies `collection_assignments_read` / `payments_read` /
-- `rider_locations_read` (00002) and the SQL helper functions
-- `rider_assigned_loan_ids` / `rider_assigned_lender_ids` (00017) reference
-- `collection_assignments.loan_id` / `payments.loan_id`, so they MUST be
-- dropped/replaced BEFORE those columns are dropped, then recreated after.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) lender_profiles — drop blacklist snapshot (source: blacklist) and
--    residence snapshot (source: addresses). source_of_funds is lender-owned
--    KYC data and is KEPT.
-- ─────────────────────────────────────────────────────────────────────────────
DROP INDEX IF EXISTS idx_lender_blacklisted;

ALTER TABLE lender_profiles
  DROP COLUMN IF EXISTS is_blacklisted,
  DROP COLUMN IF EXISTS blacklist_reason,
  DROP COLUMN IF EXISTS blacklisted_by,
  DROP COLUMN IF EXISTS blacklisted_at,
  DROP COLUMN IF EXISTS street_address,
  DROP COLUMN IF EXISTS barangay,
  DROP COLUMN IF EXISTS city,
  DROP COLUMN IF EXISTS province,
  DROP COLUMN IF EXISTS zip_code;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) loans — drop disbursement/penalty snapshots (sources: disbursements,
--    penalty_logs) and the derived financial columns.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE loans
  DROP COLUMN IF EXISTS total_payable,
  DROP COLUMN IF EXISTS outstanding_balance,
  DROP COLUMN IF EXISTS disbursed_at,
  DROP COLUMN IF EXISTS disbursement_method,
  DROP COLUMN IF EXISTS xendit_disbursement_id,
  DROP COLUMN IF EXISTS penalty_applied,
  DROP COLUMN IF EXISTS penalty_amount,
  DROP COLUMN IF EXISTS penalty_applied_at,
  DROP COLUMN IF EXISTS penalty_applied_by;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) loan_schedules — drop derived columns (source: payments).
-- ─────────────────────────────────────────────────────────────────────────────
DROP INDEX IF EXISTS idx_loan_schedules_status;

ALTER TABLE loan_schedules
  DROP COLUMN IF EXISTS amount_paid,
  DROP COLUMN IF EXISTS status,
  DROP COLUMN IF EXISTS paid_at;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4a) Pre-drop dependent RLS objects. The policies below (from 00002) reference
--     collection_assignments.loan_id / payments.loan_id directly; the SQL
--     helper functions (from 00017) reference collection_assignments.loan_id.
--     They must be dropped/replaced BEFORE the columns are dropped.
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "collection_assignments_read" ON collection_assignments;
DROP POLICY IF EXISTS "payments_read" ON payments;
DROP POLICY IF EXISTS "rider_locations_read" ON rider_locations;

-- Replace the SQL helper functions with versions that resolve loan ids
-- through loan_schedules (no more collection_assignments.loan_id).
CREATE OR REPLACE FUNCTION rider_assigned_loan_ids()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT loan_id FROM credit_investigations WHERE rider_id = auth.uid()
  UNION
  SELECT ls.loan_id
  FROM collection_assignments ca
  JOIN loan_schedules ls ON ls.id = ca.loan_schedule_id
  WHERE ca.rider_id = auth.uid()
$$;

CREATE OR REPLACE FUNCTION rider_assigned_lender_ids()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT l.lender_id
  FROM credit_investigations ci
  JOIN loans l ON l.id = ci.loan_id
  WHERE ci.rider_id = auth.uid()
  UNION
  SELECT l.lender_id
  FROM collection_assignments ca
  JOIN loan_schedules ls ON ls.id = ca.loan_schedule_id
  JOIN loans l ON l.id = ls.loan_id
  WHERE ca.rider_id = auth.uid()
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4b) collection_assignments — drop loan_id (transitive via loan_schedule_id)
-- ─────────────────────────────────────────────────────────────────────────────
DROP INDEX IF EXISTS idx_coll_assign_loan_id;

ALTER TABLE collection_assignments
  DROP CONSTRAINT IF EXISTS collection_assignments_loan_id_fkey,
  DROP COLUMN IF EXISTS loan_id;

-- Restore the loan-delete cascade through the schedule FK.
ALTER TABLE collection_assignments
  DROP CONSTRAINT IF EXISTS collection_assignments_loan_schedule_id_fkey,
  ADD CONSTRAINT collection_assignments_loan_schedule_id_fkey
    FOREIGN KEY (loan_schedule_id) REFERENCES loan_schedules(id) ON DELETE CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4c) payments — drop loan_id (transitive via loan_schedule_id /
--     collection_assignment_id)
-- ─────────────────────────────────────────────────────────────────────────────
DROP INDEX IF EXISTS idx_payments_loan_id;

ALTER TABLE payments
  DROP CONSTRAINT IF EXISTS payments_loan_id_fkey,
  DROP COLUMN IF EXISTS loan_id;

ALTER TABLE payments
  DROP CONSTRAINT IF EXISTS payments_loan_schedule_id_fkey,
  ADD CONSTRAINT payments_loan_schedule_id_fkey
    FOREIGN KEY (loan_schedule_id) REFERENCES loan_schedules(id) ON DELETE CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) Recreate the RLS policies with definitions that go through
--    loan_schedules (collection_assignments.loan_id is gone).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "collection_assignments_read" ON collection_assignments
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR EXISTS (
      SELECT 1
      FROM loan_schedules ls
      JOIN loans l ON l.id = ls.loan_id
      WHERE ls.id = collection_assignments.loan_schedule_id
        AND l.lender_id = auth.uid()
    )
  );

CREATE POLICY "payments_read" ON payments
  FOR SELECT TO authenticated
  USING (
    auth_role() IN ('head_manager','employee')
    OR EXISTS (
      SELECT 1
      FROM loan_schedules ls
      JOIN loans l ON l.id = ls.loan_id
      WHERE ls.id = payments.loan_schedule_id
        AND l.lender_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM collection_assignments ca
      JOIN loan_schedules ls ON ls.id = ca.loan_schedule_id
      JOIN loans l ON l.id = ls.loan_id
      WHERE ca.id = payments.collection_assignment_id
        AND l.lender_id = auth.uid()
    )
  );

CREATE POLICY "rider_locations_read" ON rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'lender'
      AND EXISTS (
        SELECT 1
        FROM collection_assignments ca
        JOIN loan_schedules ls ON ls.id = ca.loan_schedule_id
        JOIN loans l ON l.id = ls.loan_id
        WHERE ca.rider_id = rider_locations.rider_id
          AND l.lender_id = auth.uid()
          AND ca.status IN ('accepted','in_progress')
      )
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 5b) auto_mark_overdue_loans — loan_schedules.status no longer exists; derive
--     "unpaid" from the absence of verified payments.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION auto_mark_overdue_loans()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE loans
  SET status = 'overdue'
  WHERE status = 'active'
    AND id IN (
      SELECT ls.loan_id
      FROM loan_schedules ls
      LEFT JOIN payments p ON p.loan_schedule_id = ls.id AND p.status = 'verified'
      WHERE ls.due_date < (NOW() - INTERVAL '30 days')::date
      GROUP BY ls.loan_id, ls.id
      HAVING COALESCE(SUM(p.amount), 0) = 0
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6) Read-only views exposing the derived financials (single source: base tables).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_loan_financials AS
SELECT
  l.id                                    AS loan_id,
  l.principal_amount,
  l.interest_rate,
  ROUND(l.principal_amount * (1 + l.interest_rate / 100), 2) AS total_payable,
  COALESCE(pl.total_penalties, 0)         AS penalties_total,
  COALESCE(pm.total_paid, 0)              AS payments_total,
  GREATEST(
    0,
    ROUND(l.principal_amount * (1 + l.interest_rate / 100), 2)
    + COALESCE(pl.total_penalties, 0)
    - COALESCE(pm.total_paid, 0)
  )                                       AS outstanding_balance
FROM loans l
LEFT JOIN (
  SELECT loan_id, SUM(penalty_amount) AS total_penalties
  FROM penalty_logs
  GROUP BY loan_id
) pl ON pl.loan_id = l.id
LEFT JOIN (
  SELECT ls.loan_id, SUM(p.amount) AS total_paid
  FROM payments p
  JOIN loan_schedules ls ON ls.id = p.loan_schedule_id
  WHERE p.status = 'verified'
  GROUP BY ls.loan_id
) pm ON pm.loan_id = l.id;

CREATE OR REPLACE VIEW v_loan_schedules AS
SELECT
  s.id,
  s.loan_id,
  s.installment_number,
  s.due_date,
  s.amount_due,
  COALESCE(p.amount_paid, 0) AS amount_paid,
  CASE
    WHEN COALESCE(p.amount_paid, 0) >= s.amount_due THEN 'paid'
    WHEN COALESCE(p.amount_paid, 0) > 0 THEN 'partial'
    WHEN s.due_date < CURRENT_DATE THEN 'overdue'
    ELSE 'pending'
  END AS status,
  p.last_paid_at AS paid_at,
  s.created_at,
  s.updated_at
FROM loan_schedules s
LEFT JOIN (
  SELECT loan_schedule_id, SUM(amount) AS amount_paid, MAX(paid_at) AS last_paid_at
  FROM payments
  WHERE status = 'verified'
  GROUP BY loan_schedule_id
) p ON p.loan_schedule_id = s.id;

COMMIT;
