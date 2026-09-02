-- Add read_at column to notifications so mark-read can record when a
-- notification was marked read. The notifications-mark-read handler writes
-- read_at; without the column the update fails with a DB error.
--
-- Idempotent: safe to re-run even if the column already exists
-- (00001 consolidated schema already includes read_at in the CREATE TABLE).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'notifications'
      AND column_name  = 'read_at'
  ) THEN
    ALTER TABLE notifications ADD COLUMN read_at TIMESTAMPTZ;
    RAISE NOTICE '00011: added read_at column to notifications';
  ELSE
    RAISE NOTICE '00011: read_at column already exists – skipping';
  END IF;
END
$$;
