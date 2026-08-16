-- 00018_payment_collection_requests.sql
-- Lender-initiated rider collection requests.
--
-- A lender can request a rider to collect their installment payment at home.
-- This creates a `collection_assignments` row in a new `requested` status
-- (no rider yet); the office staff then assigns an available rider to it.

-- riders / assigned_by are not known at request time, so they become nullable.
ALTER TABLE collection_assignments ALTER COLUMN rider_id DROP NOT NULL;
ALTER TABLE collection_assignments ALTER COLUMN assigned_by DROP NOT NULL;

-- Who requested the collection (the lender).
ALTER TABLE collection_assignments ADD COLUMN IF NOT EXISTS requested_by UUID REFERENCES users(id);

-- New status for lender-requested collections.
INSERT INTO collection_assignment_statuses (code, label, description, sort_order)
VALUES ('requested', 'Requested', 'Lender requested a rider to collect payment', 0)
ON CONFLICT (code) DO NOTHING;

-- Notification type used when a lender requests a rider collection.
INSERT INTO notification_types (code, label, sort_order)
VALUES ('collection_requested', 'Collection Requested', 25)
ON CONFLICT (code) DO NOTHING;

-- At most one pending request per schedule.
CREATE UNIQUE INDEX IF NOT EXISTS uq_collection_assignments_requested_schedule
  ON collection_assignments (loan_schedule_id)
  WHERE status = 'requested';