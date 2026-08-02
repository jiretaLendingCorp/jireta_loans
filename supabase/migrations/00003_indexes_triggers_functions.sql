-- supabase/migrations/00003_indexes_triggers_functions.sql
BEGIN;

CREATE TABLE IF NOT EXISTS rate_limit_logs (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  key        TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rate_limit_key        ON rate_limit_logs(key);
CREATE INDEX IF NOT EXISTS idx_rate_limit_created_at ON rate_limit_logs(created_at);

CREATE TABLE IF NOT EXISTS password_reset_tokens (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT        NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at    TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_pwd_reset_user_id ON password_reset_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_pwd_reset_token   ON password_reset_tokens(token_hash);

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

CREATE OR REPLACE FUNCTION auto_mark_overdue_loans()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE loans
  SET status = 'overdue'
  WHERE status = 'active'
    AND id IN (
      SELECT DISTINCT loan_id FROM loan_schedules
      WHERE status = 'pending'
        AND due_date < NOW() - INTERVAL '30 days'
    );
END;
$$;

COMMIT;