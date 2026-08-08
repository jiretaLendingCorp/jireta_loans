-- ═══════════════════════════════════════════════════════════════════════════
-- Jireta Loans & Credit Corp 1966
-- Migration: 00020_lender_rider_cleanup.sql
-- Purpose  : Riders & lenders identify with a PHONE number only.
--            1. Null out any synthetic email (e.g. `0964...@jireta-loans.app`)
--               that leaked into users.email for rider/lender accounts.
--            2. Remove the placeholder identity `first_name = 'Jireta'` /
--               `last_name = 'Lender'` left by older self-registration.
--            3. DB-level guard so email can never be set on rider/lender again.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1) Clean existing rows ─────────────────────────────────────────────────
UPDATE users u
SET    email      = NULL,
       first_name = CASE
                      WHEN u.first_name IN ('Jireta', '') THEN ''
                      ELSE u.first_name
                    END,
       last_name  = CASE
                      WHEN u.last_name IN ('Lender', '') THEN ''
                      ELSE u.last_name
                    END
WHERE  EXISTS (
  SELECT 1 FROM roles r
  WHERE  r.id  = u.role_id
    AND  r.name IN ('rider', 'lender')
);

-- ── 2) Guard: email must stay NULL for rider/lender accounts ───────────────
-- NOTE: first_name / last_name are intentionally NOT forced here — staff
--       create riders with real names and riders/lenders edit their own
--       names (users-update-profile). Email is the only field riders/lenders
--       must never carry.
CREATE OR REPLACE FUNCTION fn_users_rider_lender_no_email()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role VARCHAR(50);
BEGIN
  SELECT name INTO v_role FROM roles WHERE id = NEW.role_id;
  IF v_role IN ('rider', 'lender') THEN
    NEW.email := NULL;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_rider_lender_no_email
  BEFORE INSERT OR UPDATE OF role_id, email ON users
  FOR EACH ROW
  EXECUTE FUNCTION fn_users_rider_lender_no_email();

COMMIT;
