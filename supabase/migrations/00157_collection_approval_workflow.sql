-- supabase/migrations/00157_collection_approval_workflow.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Business rule: kapag nag-submit ang rider ng koleksyon, HINDI agad bumaba ang
-- balanse ng loan. Kailangan munang i-approve ng Head Manager o Employee na
-- tunay na nakuha ang pera. Sa approval lang nagiging `verified` ang payment
-- (at doon lang bumababa ang outstanding balance / nagiging `completed` ang
-- loan). Kapag ni-reject, hindi nababawasan ang loan at kailangang mag-assign
-- ng rider na mangolekta muli.
--
--   rider submit (record/upload-proof)
--     → payments.status = 'verified'         (naka-record agad, kagaya ng dati)
--     → collection_assignments.status = 'pending_approval'
--         (HINDI pa binibilang sa loan balance — may gate, tingnan 00159)
--   HM/Employee approve (fn=approve)
--     → collection_assignments.status = 'completed'  (dito lang bumababa ang loan)
--   HM/Employee reject (fn=reject)
--     → payments.status = 'rejected'
--     → collection_assignments.status = 'rejected'  (i-reassign ang rider)
--
-- Kaya: ang lender loan balance ay hindi direktang "verified lang" — kailangan
-- ding `completed` ang parent collection (tingnan ang 00159 view gate).
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- 1) Bagong collection statuses para sa approval workflow.
INSERT INTO collection_assignment_statuses (code, label, description, sort_order) VALUES
  ('pending_approval', 'Pending Approval', 'Rider submitted the collection; awaiting Head Manager/Employee review', 8),
  ('rejected',         'Rejected',         'Head Manager/Employee rejected the collection; money not received',   9)
ON CONFLICT (code) DO NOTHING;

-- 2) `rejected` na status para sa mga rider-submitted payment na tinanggihan.
--    Hindi ito binibilang sa balance (verified lang ang binibilang).
INSERT INTO payment_statuses (code, label, sort_order) VALUES
  ('rejected', 'Rejected', 4)
ON CONFLICT (code) DO NOTHING;

-- 3) Review audit trail sa collection_assignments.
ALTER TABLE collection_assignments
  ADD COLUMN IF NOT EXISTS reviewed_by      UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS reviewed_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

-- 4) Notification types para sa workflow.
INSERT INTO notification_types (code, label, sort_order) VALUES
  ('collection_pending_approval', 'Collection Pending Approval', 32),
  ('collection_approved',         'Collection Approved',         33),
  ('collection_rejected',         'Collection Rejected',         34)
ON CONFLICT (code) DO NOTHING;

-- 5) Ang isang 'pending_approval' na koleksyon ay ACTIVE pa rin para sa rider —
--    isama sa partial unique index para hindi mabigyan ng dobleng aktibong
--    koleksyon ang parehong rider para sa parehong schedule habang nakabinbin.
DROP INDEX IF EXISTS uq_collection_assignments_active_schedule_rider;
CREATE UNIQUE INDEX uq_collection_assignments_active_schedule_rider
  ON collection_assignments (loan_schedule_id, rider_id)
  WHERE status IN ('assigned','accepted','in_progress','pending_approval');

COMMIT;
