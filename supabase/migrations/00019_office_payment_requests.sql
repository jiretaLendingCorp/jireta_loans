-- 00019_office_payment_requests.sql
-- Office visit payment requests.
--
-- A lender can signal that they will visit the office to pay an installment,
-- just like the rider collection request. This reuses `collection_assignments`
-- in the `requested` status, distinguished by a `collection_type` column.
-- The office staff sees the request and records the payment when the lender
-- arrives (which completes the request).

-- Distinguishes the collection request type: rider (home collection) or
-- office (lender pays at the office).
ALTER TABLE collection_assignments ADD COLUMN IF NOT EXISTS collection_type TEXT NOT NULL DEFAULT 'rider';
COMMENT ON COLUMN collection_assignments.collection_type IS 'rider | office';

-- Notification type used when a lender requests to pay at the office.
INSERT INTO notification_types (code, label, sort_order)
VALUES ('office_payment_requested', 'Office Payment Requested', 26)
ON CONFLICT (code) DO NOTHING;