-- =====================================================================
-- Migration : 00123_ensure_roles_exist_for_auth_sync.sql
-- Purpose   : Fix "role head_manager not found in public.roles" error.
--
-- The log shows: handle_new_auth_user sync FAILED: role head_manager
-- not found in public.roles (SQLSTATE: P0001)
--
-- The 00004 seed data INSERT INTO roles may not have been applied to
-- the cloud database, or roles were deleted. This migration:
--   1) Ensures all 4 core roles exist (idempotent)
--   2) Also ensures the 'active' account_status exists
--   3) Recovers gracefully if either is missing
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- Ensure core roles exist (idempotent — ON CONFLICT prevents duplicates)
INSERT INTO roles (name, description) VALUES
  ('head_manager', 'Full system access - web portal'),
  ('employee',     'Loan processing and management - web portal'),
  ('rider',        'Field agent for CI and collections - mobile'),
  ('lender',       'Borrower who applies for loans - mobile')
ON CONFLICT (name) DO NOTHING;

-- Ensure account_status 'active' exists (needed by handle_new_auth_user)
INSERT INTO user_account_statuses (code, label, sort_order) VALUES
  ('active',   'Active',   1),
  ('inactive', 'Inactive', 2),
  ('archived', 'Archived', 4)
ON CONFLICT (code) DO NOTHING;

-- Verify and report
DO $$
DECLARE
  v_cnt INT;
BEGIN
  SELECT COUNT(*) INTO v_cnt FROM roles;
  RAISE NOTICE 'roles table now has % rows', v_cnt;

  IF NOT EXISTS (SELECT 1 FROM roles WHERE name = 'head_manager') THEN
    RAISE WARNING 'CRITICAL: head_manager role still missing after insert!';
  ELSE
    RAISE NOTICE 'head_manager role confirmed present';
  END IF;
END $$;

COMMIT;
