-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00002_functions_triggers_views.sql
-- Purpose   : Consolidated functions, triggers, and views. Reproduces the
--             end-state of the original migrations — only the FINAL version
--             of each object is emitted (functions that were redefined over
--             several migrations appear once, with their latest body).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) updated_at maintenance
--    set_updated_at() fires BEFORE UPDATE on every table that carries an
--    updated_at column, keeping the timestamp current automatically.
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- Domain tables (00001)
CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_lender_updated_at
  BEFORE UPDATE ON lender_profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_rider_updated_at
  BEFORE UPDATE ON rider_profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_employee_updated_at
  BEFORE UPDATE ON employee_profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_addresses_updated_at
  BEFORE UPDATE ON addresses FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_loans_updated_at
  BEFORE UPDATE ON loans FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_loan_schedules_updated_at
  BEFORE UPDATE ON loan_schedules FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_in_office_updated_at
  BEFORE UPDATE ON in_office_applications FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_ci_updated_at
  BEFORE UPDATE ON credit_investigations FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_collection_updated_at
  BEFORE UPDATE ON collection_assignments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_disbursements_updated_at
  BEFORE UPDATE ON disbursements FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- co_makers (00022) and loan_disbursement_preferences (00031) picked up
-- updated_at when they were added
CREATE TRIGGER trg_co_makers_updated_at
  BEFORE UPDATE ON co_makers FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_loan_disb_prefs_updated_at
  BEFORE UPDATE ON loan_disbursement_preferences FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Reference (lookup) tables (00025) — same trigger on all 21
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'user_account_statuses','account_upgrade_statuses','loan_statuses','payment_statuses',
    'payment_methods','disbursement_methods','disbursement_statuses',
    'collection_assignment_statuses','credit_investigation_statuses',
    'notification_types','relationship_types','payment_frequencies',
    'address_types','document_types','gender_types','civil_statuses',
    'employment_types','vehicle_types','platform_types','sms_statuses',
    'in_office_application_statuses'
  ] LOOP
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at();',
                   'trg_' || t || '_updated_at', t);
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 2) auth_role() — the role of the authenticated user. Used by nearly
--    every RLS policy to scope access by head_manager / employee / rider /
--    lender. SECURITY DEFINER so policies can call it without recursion.
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION auth_role()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT r.name
  FROM users u
  JOIN roles r ON r.id = u.role_id
  WHERE u.id = auth.uid()
    AND u.account_status = 'active'
  LIMIT 1;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 3) Auth lifecycle triggers (00005) — automate audit-log bookkeeping and
--    DB-level safety nets around login / OTP / password management.
-- ─────────────────────────────────────────────────────────────────────

-- 3a) last_login_at propagates automatically from a login_success event
CREATE OR REPLACE FUNCTION fn_auth_update_last_login()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE users
  SET last_login_at = NEW.created_at
  WHERE id = NEW.user_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auth_update_last_login
  AFTER INSERT ON auth_logs
  FOR EACH ROW
  WHEN (NEW.event_type = 'login_success')
  EXECUTE FUNCTION fn_auth_update_last_login();

-- 3b) A dedicated account_locked audit event is written when the 5th
--     login failure marks the account locked
CREATE OR REPLACE FUNCTION fn_auth_record_account_locked()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO auth_logs (
    user_id,
    event_type,
    ip_address,
    user_agent,
    failed_attempts,
    is_locked
  )
  VALUES (
    NEW.user_id,
    'account_locked',
    NEW.ip_address,
    NEW.user_agent,
    NEW.failed_attempts,
    TRUE
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auth_record_account_locked
  AFTER INSERT ON auth_logs
  FOR EACH ROW
  WHEN (NEW.event_type = 'login_fail' AND NEW.is_locked = TRUE)
  EXECUTE FUNCTION fn_auth_record_account_locked();

-- 3c) OTP guard — block OTP inserts for archived/inactive accounts.
--     Unregistered phones are allowed (lender self-registration).
--     Final version (00034): 'suspended' no longer exists.
CREATE OR REPLACE FUNCTION fn_otp_guard_account_status()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_status VARCHAR(20);
BEGIN
  SELECT account_status
  INTO   v_status
  FROM   users
  WHERE  phone_number = NEW.phone_number
  LIMIT  1;

  -- Unregistered phone: allow OTP so lenders can self-register.
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF v_status IN ('archived', 'inactive') THEN
    RAISE EXCEPTION 'Cannot send OTP — account is %', v_status
      USING ERRCODE = 'P0002';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_otp_guard_account_status
  BEFORE INSERT ON otp_codes
  FOR EACH ROW
  EXECUTE FUNCTION fn_otp_guard_account_status();

-- 3d) Atomically invalidate all prior active OTPs for a phone when a
--     new one is issued (kills the race window in the edge function)
CREATE OR REPLACE FUNCTION fn_otp_invalidate_previous()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE otp_codes
  SET    used = TRUE
  WHERE  phone_number = NEW.phone_number
    AND  used         = FALSE
    AND  id          != NEW.id;          -- spare the row we just inserted
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_otp_invalidate_previous
  AFTER INSERT ON otp_codes
  FOR EACH ROW
  EXECUTE FUNCTION fn_otp_invalidate_previous();

-- 3e) Log an otp_fail audit event when an OTP hits the 5-attempt ceiling
CREATE OR REPLACE FUNCTION fn_otp_log_max_attempts()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id UUID;
BEGIN
  SELECT id
  INTO   v_user_id
  FROM   users
  WHERE  phone_number = NEW.phone_number
  LIMIT  1;

  IF v_user_id IS NOT NULL THEN
    INSERT INTO auth_logs (
      user_id,
      event_type,
      failed_attempts,
      is_locked
    )
    VALUES (
      v_user_id,
      'otp_fail',
      NEW.attempts,
      FALSE
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_otp_log_max_attempts
  AFTER UPDATE OF attempts ON otp_codes
  FOR EACH ROW
  WHEN (OLD.attempts < 5 AND NEW.attempts >= 5)
  EXECUTE FUNCTION fn_otp_log_max_attempts();

-- 3f) Log force_password_changed when a user completes the mandatory
--     first-login password reset
CREATE OR REPLACE FUNCTION fn_users_log_force_password_changed()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO auth_logs (
    user_id,
    event_type,
    failed_attempts,
    is_locked
  )
  VALUES (
    NEW.id,
    'force_password_changed',
    0,
    FALSE
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_log_force_password_changed
  AFTER UPDATE OF force_password_change ON users
  FOR EACH ROW
  WHEN (OLD.force_password_change = TRUE AND NEW.force_password_change = FALSE)
  EXECUTE FUNCTION fn_users_log_force_password_changed();

-- 3g) Keep only the last 5 password hashes per user
CREATE OR REPLACE FUNCTION fn_password_history_trim()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  DELETE FROM password_history
  WHERE  user_id = NEW.user_id
    AND  id NOT IN (
           SELECT id
           FROM   password_history
           WHERE  user_id = NEW.user_id
           ORDER  BY created_at DESC
           LIMIT  5
         );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_password_history_trim
  AFTER INSERT ON password_history
  FOR EACH ROW
  EXECUTE FUNCTION fn_password_history_trim();

-- ─────────────────────────────────────────────────────────────────────
-- 4) Rider/lender email guard
--    Riders & lenders identify with a PHONE number. A real email is kept
--    (Google OAuth lenders); only synthetic temp credentials
--    (`%@jireta.temp`) and empty values are stripped. Final version (00033).
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_users_rider_lender_no_email()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role VARCHAR(50);
BEGIN
  SELECT name INTO v_role FROM roles WHERE id = NEW.role_id;
  IF v_role IN ('rider', 'lender') THEN
    IF NEW.email IS NULL OR NEW.email ILIKE '%@jireta.temp' THEN
      NEW.email := NULL;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_rider_lender_no_email
  BEFORE INSERT OR UPDATE OF role_id, email ON users
  FOR EACH ROW
  EXECUTE FUNCTION fn_users_rider_lender_no_email();

-- ─────────────────────────────────────────────────────────────────────
-- 5) Maintenance / cleanup functions (00003, 00021)
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION cleanup_expired_otps()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM otp_codes WHERE expires_at < NOW() - INTERVAL '1 hour';
END;
$$;

CREATE OR REPLACE FUNCTION cleanup_rate_limit_logs()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM rate_limit_logs WHERE created_at < NOW() - INTERVAL '1 hour';
END;
$$;

-- Marks active loans overdue when a schedule is > 30 days past due with
-- no verified payment. Final version (00021): loan_schedules.status is
-- derived, so "unpaid" is detected by the absence of verified payments.
CREATE OR REPLACE FUNCTION auto_mark_overdue_loans()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE loans
  SET status = 'overdue'
  WHERE status = 'active'
    AND id IN (
      SELECT ls.loan_id
      FROM loan_schedules ls
      LEFT JOIN payments p ON p.loan_schedule_id = ls.id AND p.status = 'verified'
      WHERE ls.due_date < (NOW() - INTERVAL '30 days')::date
      GROUP BY ls.loan_id, ls.id
      HAVING COALESCE(SUM(p.amount), 0) = 0
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 6) RLS helper functions — break the policy recursion cycle
--    (SECURITY DEFINER: run as owner, bypass RLS). Final versions (00017,
--    00021): collection_assignments resolve loans through loan_schedules
--    since collection_assignments.loan_id was dropped in the 3NF pass.
-- ─────────────────────────────────────────────────────────────────────

-- Loan ids the current user owns (is the lender on)
CREATE OR REPLACE FUNCTION auth_own_loan_ids()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT id FROM loans WHERE lender_id = auth.uid()
$$;

-- Loan ids a rider is assigned to (CI or collection)
CREATE OR REPLACE FUNCTION rider_assigned_loan_ids()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT loan_id FROM credit_investigations WHERE rider_id = auth.uid()
  UNION
  SELECT ls.loan_id
  FROM collection_assignments ca
  JOIN loan_schedules ls ON ls.id = ca.loan_schedule_id
  WHERE ca.rider_id = auth.uid()
$$;

-- Lender (user) ids a rider is assigned to work with (via CI or collection)
CREATE OR REPLACE FUNCTION rider_assigned_lender_ids()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT l.lender_id
  FROM credit_investigations ci
  JOIN loans l ON l.id = ci.loan_id
  WHERE ci.rider_id = auth.uid()
  UNION
  SELECT l.lender_id
  FROM collection_assignments ca
  JOIN loan_schedules ls ON ls.id = ca.loan_schedule_id
  JOIN loans l ON l.id = ls.loan_id
  WHERE ca.rider_id = auth.uid()
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 7) Loan status flow guard — enforce the loan lifecycle at the DB level.
--    Final version (00032): INSERTs must start in a pre-approval status and
--    UPDATEs may only reach approved/active from the allowed predecessors.
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION enforce_loan_status_flow()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status IN ('approved', 'active', 'completed', 'overdue') THEN
      RAISE EXCEPTION 'Loan must be created as a pre-approval status (got %)', NEW.status;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status = 'approved' AND OLD.status NOT IN ('pending', 'under_review', 'ci_required', 'ci_assigned', 'ci_completed') THEN
    RAISE EXCEPTION 'Loan cannot be approved from % status (was %)', NEW.status, OLD.status;
  END IF;
  IF NEW.status = 'active' AND OLD.status NOT IN ('approved', 'active', 'completed', 'overdue') THEN
    RAISE EXCEPTION 'Loan must be approved before becoming active (was %)', OLD.status;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_loan_status_flow
  BEFORE UPDATE ON loans
  FOR EACH ROW
  WHEN (NEW.status IS DISTINCT FROM OLD.status)
  EXECUTE FUNCTION enforce_loan_status_flow();

CREATE TRIGGER trg_loan_status_flow_insert
  BEFORE INSERT ON loans
  FOR EACH ROW
  EXECUTE FUNCTION enforce_loan_status_flow();

-- ─────────────────────────────────────────────────────────────────────
-- 8) application_owner() — creator lookup for the in-office application
--    child tables (00022), used by their RLS read policies.
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION application_owner(application_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT created_by FROM in_office_applications WHERE id = application_id
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 9) Read-only views exposing derived financials (00021). Single source
--    of truth: the base tables. Payment status is filtered to 'verified'
--    so only settled amounts count toward principal/interest/penalties.
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW v_loan_financials AS
SELECT
  l.id                                    AS loan_id,
  l.principal_amount,
  l.interest_rate,
  ROUND(l.principal_amount * (1 + l.interest_rate / 100), 2) AS total_payable,
  COALESCE(pl.total_penalties, 0)         AS penalties_total,
  COALESCE(pm.total_paid, 0)              AS payments_total,
  GREATEST(
    0,
    ROUND(l.principal_amount * (1 + l.interest_rate / 100), 2)
    + COALESCE(pl.total_penalties, 0)
    - COALESCE(pm.total_paid, 0)
  )                                       AS outstanding_balance
FROM loans l
LEFT JOIN (
  SELECT loan_id, SUM(penalty_amount) AS total_penalties
  FROM penalty_logs
  GROUP BY loan_id
) pl ON pl.loan_id = l.id
LEFT JOIN (
  SELECT ls.loan_id, SUM(p.amount) AS total_paid
  FROM payments p
  JOIN loan_schedules ls ON ls.id = p.loan_schedule_id
  WHERE p.status = 'verified'
  GROUP BY ls.loan_id
) pm ON pm.loan_id = l.id;

CREATE OR REPLACE VIEW v_loan_schedules AS
SELECT
  s.id,
  s.loan_id,
  s.installment_number,
  s.due_date,
  s.amount_due,
  COALESCE(p.amount_paid, 0) AS amount_paid,
  CASE
    WHEN COALESCE(p.amount_paid, 0) >= s.amount_due THEN 'paid'
    WHEN COALESCE(p.amount_paid, 0) > 0 THEN 'partial'
    WHEN s.due_date < CURRENT_DATE THEN 'overdue'
    ELSE 'pending'
  END AS status,
  p.last_paid_at AS paid_at,
  s.created_at,
  s.updated_at
FROM loan_schedules s
LEFT JOIN (
  SELECT loan_schedule_id, SUM(amount) AS amount_paid, MAX(paid_at) AS last_paid_at
  FROM payments
  WHERE status = 'verified'
  GROUP BY loan_schedule_id
) p ON p.loan_schedule_id = s.id;

COMMIT;
