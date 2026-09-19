-- Migration 00169: Opaque reset-flow token for email password reset
--
-- WHY: the web reset screen used to carry the account email in the URL
-- (`/reset-password?email=user@example.com`). Query strings leak into browser
-- history, server/proxy access logs, analytics and the Referer header of
-- third-party requests, so PII must never travel there.
--
-- auth-password?fn=forgot-password now mints a 256-bit random token
-- (functions/_shared/reset_token.ts) and returns it to the client. The client
-- puts the token in the URL instead:
--
--   /reset-password?t=<64 hex chars>
--
-- Only the SHA-256 hash of that token is stored here, so the row cannot be
-- replayed from a database dump. verify-otp / reset-password accept the token
-- and resolve the email server-side, which means the email is never needed in
-- the request either.

BEGIN;
SET search_path = public, extensions;

ALTER TABLE email_reset_otps
  ADD COLUMN IF NOT EXISTS reset_token_hash TEXT;

-- One live row per token. Partial so legacy rows (NULL) do not collide.
CREATE UNIQUE INDEX IF NOT EXISTS uq_email_otp_reset_token
  ON email_reset_otps(reset_token_hash)
  WHERE reset_token_hash IS NOT NULL;

COMMENT ON COLUMN email_reset_otps.reset_token_hash IS
  'SHA-256 of the opaque reset-flow token handed to the client. The URL carries the raw token (see /reset-password?t=...); the email never appears in a URL.';

COMMIT;
