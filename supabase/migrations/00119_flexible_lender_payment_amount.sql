-- Migration 00119: Flexible Lender Payment Amount
-- Business Rule Change:
--   Lender can now specify any amount when requesting a payment collection
--   (rider or office), not only the fixed installment amount.
--   System validates: amount > 0, amount <= outstanding_balance,
--   and allocates flexibly across unpaid installments (allocatePayment).
--
-- Changes:
--   - Add requested_amount to collection_assignments to store lender's intended amount
--   - Add index for requested_amount
--   - Keep existing amount_collected for actual collected amount (filled by rider/staff)
BEGIN;
SET search_path = public, extensions;

ALTER TABLE collection_assignments
  ADD COLUMN IF NOT EXISTS requested_amount DECIMAL(12,2) CHECK (requested_amount > 0);

CREATE INDEX IF NOT EXISTS idx_collection_requested_amount ON collection_assignments(requested_amount);

-- Allow office collection type to have requested_amount as well (already collection_type enum includes office/rider)

COMMIT;
