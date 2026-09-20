-- Migration 00170: Email verification via LINK (not OTP)
--
-- WHY: pagkatapos ng "Fill In Information" modal (Terms & Conditions) ay kailangan
-- pang kumpirmahin ng lender na sa kanya talaga ang email address na inilagay niya.
-- Ang dating email flows (email_reset_otps, email_register_otps) ay 6-digit OTP —
-- dito, LINK ang ipinapadala ng Resend at ang pag-tap sa link na iyon ang
-- nagpapatunay (walang code na ita-type sa app).
--
-- Pattern na sinusundan: tanging SHA-256 hash ng token ang naka-store (tingnan ang
-- _shared/reset_token.ts), kaya kahit may makakuha ng database dump ay hindi
-- ma-replay ang link.

BEGIN;
SET search_path = public, extensions;

-- ── 1. Verification state sa account ────────────────────────────────────────
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMPTZ;

COMMENT ON COLUMN users.email_verified_at IS
  'Kailan kinumpirma ng user ang email address niya sa pamamagitan ng link na ipinadala sa email (hindi OTP code). NULL = hindi pa verified.';

-- ── 2. One-time verification links ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS email_verifications (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID        NOT NULL,
  email      TEXT        NOT NULL,
  token_hash TEXT        NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at    TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_email_verification_token
  ON email_verifications(token_hash);
CREATE INDEX IF NOT EXISTS idx_email_verification_user
  ON email_verifications(user_id);
CREATE INDEX IF NOT EXISTS idx_email_verification_email
  ON email_verifications(email);
CREATE INDEX IF NOT EXISTS idx_email_verification_live
  ON email_verifications(user_id) WHERE used_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_email_verification_expires
  ON email_verifications(expires_at);

ALTER TABLE email_verifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE email_verifications FROM anon, authenticated;

-- Kapag may bagong link na ginawa, awtomatikong pinapatay ang mga lumang hindi
-- pa nagagamit na link ng parehong account (isang live na link lang sa isang
-- pagkakataon — kapareho ng fn_register_otp_invalidate_previous).
CREATE OR REPLACE FUNCTION fn_email_verification_invalidate_previous()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE email_verifications
  SET used_at = NOW()
  WHERE user_id = NEW.user_id
    AND id <> NEW.id
    AND used_at IS NULL;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_email_verification_invalidate_previous
  ON email_verifications;
CREATE TRIGGER trg_email_verification_invalidate_previous
  AFTER INSERT ON email_verifications
  FOR EACH ROW EXECUTE FUNCTION fn_email_verification_invalidate_previous();

-- ── 3. Cleanup ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION cleanup_expired_email_verifications()
RETURNS VOID AS $$
BEGIN
  DELETE FROM email_verifications WHERE expires_at < NOW() - INTERVAL '1 day';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
