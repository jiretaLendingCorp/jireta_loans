-- /supabase/migrations/00016_fix_kyc_notifications.sql
-- 1) The notifications.type CHECK only allowed a fixed set of values, but the
--    edge functions send many more (kyc_submitted, kyc_update, loan_approved,
--    payment_verified, ...). Combined with the (fixed) code writing to the
--    wrong column this silently dropped EVERY notification. Relax the
--    constraint so notifications are always persisted.
-- 2) kyc_documents.file_path was VARCHAR(255) but the old kyc-submit stored raw
--    base64 into it (silently failing). Widen to TEXT to be safe.

BEGIN;

ALTER TABLE notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;

CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);
CREATE INDEX IF NOT EXISTS idx_notifications_user_type
  ON notifications(user_id, type, created_at DESC);

-- Widening is a no-op if the column is already TEXT.
ALTER TABLE kyc_documents
  ALTER COLUMN file_path TYPE TEXT;

COMMIT;
