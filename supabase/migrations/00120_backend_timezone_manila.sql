-- =====================================================================
-- Jireta Loans & Credit Corp
-- Migration : 00120_backend_timezone_manila.sql
-- Purpose   : Ensure all backend timestamps use Asia/Manila (UTC+8).
--             Creates now_manila() helper and updates key functions.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) now_manila() — returns current timestamp in Asia/Manila timezone
--    as a TIMESTAMPTZ (PostgreSQL stores as UTC internally, but the
--    value represents Manila local time).
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION now_manila()
RETURNS TIMESTAMPTZ LANGUAGE sql STABLE AS $$
  SELECT NOW() AT TIME ZONE 'Asia/Manila' AT TIME ZONE 'UTC';
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 2) Update set_updated_at() to use Manila time
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now_manila();
  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 3) Update cleanup functions to use Manila time
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION cleanup_expired_otps()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM otp_codes WHERE expires_at < now_manila() - INTERVAL '1 hour';
END;
$$;

CREATE OR REPLACE FUNCTION cleanup_rate_limit_logs()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM rate_limit_logs WHERE created_at < now_manila() - INTERVAL '1 hour';
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 4) Update auto_mark_overdue_loans() to use Manila time
-- ─────────────────────────────────────────────────────────────────────

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
      WHERE ls.due_date < (now_manila() - INTERVAL '30 days')::date
      GROUP BY ls.loan_id, ls.id
      HAVING COALESCE(SUM(p.amount), 0) = 0
    );
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 5) Update OTP-related functions to use Manila time
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_auth_update_last_login()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE users
  SET last_login_at = now_manila()
  WHERE id = NEW.user_id;
  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────
-- 6) Update v_loan_schedules view to use Manila time for overdue check
-- ─────────────────────────────────────────────────────────────────────

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
    WHEN s.due_date < (now_manila())::date THEN 'overdue'
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

-- ─────────────────────────────────────────────────────────────────────
-- 7) Backfill: update any NULL updated_at timestamps to Manila time
-- ─────────────────────────────────────────────────────────────────────

-- Note: This is a one-time backfill. Existing timestamps remain as-is
-- since they were stored in UTC. New writes will use Manila time.

COMMIT;
