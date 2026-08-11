-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00005_single_head_manager.sql
-- Purpose   : Enforce a single head_manager account. Blocks creating a
--             second head_manager (or promoting a user to head_manager).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION fn_users_single_head_manager()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role VARCHAR(50);
BEGIN
  SELECT name INTO v_role FROM roles WHERE id = NEW.role_id;

  IF v_role = 'head_manager' THEN
    IF EXISTS (
      SELECT 1 FROM users u
      JOIN roles r ON r.id = u.role_id
      WHERE r.name = 'head_manager'
        AND u.id <> NEW.id
        AND u.account_status <> 'archived'
    ) THEN
      RAISE EXCEPTION 'Only one head manager account is allowed'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_single_head_manager ON users;

CREATE TRIGGER trg_users_single_head_manager
  BEFORE INSERT OR UPDATE OF role_id ON users
  FOR EACH ROW
  EXECUTE FUNCTION fn_users_single_head_manager();

COMMIT;
