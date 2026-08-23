-- Migration 00104: Email OTP for password reset (6-digit code flow)
-- Replaces link-based recovery with OTP-based flow per spec:
-- Forgot Password -> Generate 6-digit OTP -> Hash + save -> Resend -> Verify -> New Password

BEGIN;
SET search_path = public, extensions;

-- Email OTP table for password reset (separate from phone otp_codes)
CREATE TABLE IF NOT EXISTS email_reset_otps (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  email      TEXT        NOT NULL,
  otp_hash   TEXT        NOT NULL,
  attempts   INT         NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  expires_at TIMESTAMPTZ NOT NULL,
  used       BOOLEAN     NOT NULL DEFAULT FALSE,
  verified   BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_email_otp_user_id ON email_reset_otps(user_id);
CREATE INDEX IF NOT EXISTS idx_email_otp_email ON email_reset_otps(email);
CREATE INDEX IF NOT EXISTS idx_email_otp_expires ON email_reset_otps(expires_at);
CREATE INDEX IF NOT EXISTS idx_email_otp_email_unused ON email_reset_otps(email) WHERE used = FALSE;

ALTER TABLE email_reset_otps ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE email_reset_otps FROM anon, authenticated;

-- Invalidate previous unused OTPs for same email when new one is created
CREATE OR REPLACE FUNCTION fn_email_otp_invalidate_previous()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE email_reset_otps
  SET used = TRUE
  WHERE email = NEW.email
    AND id <> NEW.id
    AND used = FALSE;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_email_otp_invalidate_previous ON email_reset_otps;
CREATE TRIGGER trg_email_otp_invalidate_previous
  AFTER INSERT ON email_reset_otps
  FOR EACH ROW EXECUTE FUNCTION fn_email_otp_invalidate_previous();

-- Lockout table for email OTP verify brute force (escalating)
CREATE TABLE IF NOT EXISTS email_otp_lockouts (
  email           TEXT PRIMARY KEY,
  failed_attempts INT         NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
  locked_until    TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_email_otp_lockouts_locked_until ON email_otp_lockouts(locked_until);
ALTER TABLE email_otp_lockouts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE email_otp_lockouts FROM anon, authenticated;

-- Cleanup expired OTPs (expired > 1 hour ago)
CREATE OR REPLACE FUNCTION cleanup_expired_email_otps()
RETURNS VOID AS $$
BEGIN
  DELETE FROM email_reset_otps WHERE expires_at < NOW() - INTERVAL '1 hour';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
