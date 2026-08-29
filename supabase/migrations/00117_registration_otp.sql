-- Migration 00117: Registration OTP (employee self-register via email)
-- Flow: Fill form -> Send OTP (Resend/Gmail) -> Enter OTP -> Verify -> Create account
-- Reuses same 6-digit, SHA-256 hashed pattern as email_reset_otps but separate table
-- so password-reset and registration codes never collide.

BEGIN;
SET search_path = public, extensions;

-- Registration OTP table
CREATE TABLE IF NOT EXISTS email_register_otps (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email      TEXT        NOT NULL,
  otp_hash   TEXT        NOT NULL,
  attempts   INT         NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  expires_at TIMESTAMPTZ NOT NULL,
  used       BOOLEAN     NOT NULL DEFAULT FALSE,
  verified   BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_register_otp_email ON email_register_otps(email);
CREATE INDEX IF NOT EXISTS idx_register_otp_expires ON email_register_otps(expires_at);
CREATE INDEX IF NOT EXISTS idx_register_otp_email_unused ON email_register_otps(email) WHERE used = FALSE;

ALTER TABLE email_register_otps ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE email_register_otps FROM anon, authenticated;

-- Invalidate previous unused OTPs for same email when new one is created
CREATE OR REPLACE FUNCTION fn_register_otp_invalidate_previous()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE email_register_otps
  SET used = TRUE
  WHERE email = NEW.email
    AND id <> NEW.id
    AND used = FALSE;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_register_otp_invalidate_previous ON email_register_otps;
CREATE TRIGGER trg_register_otp_invalidate_previous
  AFTER INSERT ON email_register_otps
  FOR EACH ROW EXECUTE FUNCTION fn_register_otp_invalidate_previous();

-- Lockout table for registration OTP brute force (escalating)
CREATE TABLE IF NOT EXISTS email_register_lockouts (
  email           TEXT PRIMARY KEY,
  failed_attempts INT         NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
  locked_until    TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_register_lockouts_locked_until ON email_register_lockouts(locked_until);
ALTER TABLE email_register_lockouts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE email_register_lockouts FROM anon, authenticated;

-- Cleanup expired OTPs (expired > 1 hour ago)
CREATE OR REPLACE FUNCTION cleanup_expired_register_otps()
RETURNS VOID AS $$
BEGIN
  DELETE FROM email_register_otps WHERE expires_at < NOW() - INTERVAL '1 hour';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
