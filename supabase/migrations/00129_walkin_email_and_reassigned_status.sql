-- Migration: 00129_walkin_email_and_reassigned_status.sql
-- Purpose: support walk-in wizard email field + CI reassigned audit status.
BEGIN;
SET search_path = public, extensions;

ALTER TABLE application_personal_info
  ADD COLUMN IF NOT EXISTS email VARCHAR(255);

-- Allow 'reassigned' status for superseded CI rows (old failed/expired/declined
-- kept for audit after a new rider is assigned).
DO $$
BEGIN
  BEGIN
    ALTER TABLE credit_investigations DROP CONSTRAINT IF EXISTS credit_investigations_status_check;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    ALTER TABLE credit_investigations
      ADD CONSTRAINT credit_investigations_status_check CHECK (
        status IN ('assigned','in_progress','completed','approved','rejected','failed','expired','declined','reassigned')
      );
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

COMMIT;
