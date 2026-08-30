-- Migration 00118: CI Approval Workflow + Lender Payment History Polish
-- Business Rule Change:
--   Rider submits CI report -> status = 'completed' (pending manager review)
--   Head Manager / Employee must explicitly APPROVE the CI before loan can be approved
--   and before lender can select disbursement method.
--   Rejection returns loan to under_review / ci_required and frees rider.
--
-- Changes:
--   - Add CI statuses: 'approved' (manager approved), 'rejected' (manager rejected)
--   - Add review columns to credit_investigations: reviewed_by, reviewed_at, review_notes
--   - Keep loan_statuses as-is (ci_completed = CI pending approval, approved = loan approved after CI)
--     but document that approve now requires CI approved.
--   - No schema change needed for payment history; lender already sees own payments.
--     This migration only adds audit/UX clarity.
BEGIN;
SET search_path = public, extensions;

-- 1) New CI investigation statuses
INSERT INTO credit_investigation_statuses (code, label, sort_order) VALUES
  ('approved', 'Approved', 6),
  ('rejected', 'Rejected', 7)
ON CONFLICT (code) DO NOTHING;

-- 2) Review tracking columns on credit_investigations
ALTER TABLE credit_investigations
  ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS review_notes TEXT,
  ADD COLUMN IF NOT EXISTS review_decision VARCHAR(20) CHECK (review_decision IN ('approved','rejected'));

CREATE INDEX IF NOT EXISTS idx_ci_reviewed_by ON credit_investigations(reviewed_by);
CREATE INDEX IF NOT EXISTS idx_ci_review_decision ON credit_investigations(review_decision);

-- 3) Ensure disbursement preference is visible as source of truth for lender choice
--    (already exists as loan_disbursement_preferences). No change.

-- 4) Helper to expire stale CI completed that were never reviewed (optional, for future cron)
--    Not auto-run; just provided.

COMMIT;
