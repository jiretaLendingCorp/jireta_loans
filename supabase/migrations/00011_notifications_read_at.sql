-- Add read_at column to notifications so mark-read can record when a
-- notification was marked read. The notifications-mark-read handler writes
-- read_at; without the column the update fails with a DB error.
ALTER TABLE notifications ADD COLUMN read_at TIMESTAMPTZ;