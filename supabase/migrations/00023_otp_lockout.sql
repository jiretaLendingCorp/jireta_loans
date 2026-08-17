-- supabase/migrations/00023_otp_lockout.sql
--
-- Persistent, escalating OTP verification lockout.
--
--   otp_lockouts — per-phone record of consecutive failed OTP attempts with a
--                  lockout expiry. Persists server-side, so closing the app or
--                  requesting a fresh OTP can NOT reset the count (a user must
--                  either wait out the lock or verify successfully).
--
-- Escalation schedule (matches product spec):
--   3 failed attempts  → 3 minutes
--   4 failed attempts  → 10 minutes
--   5+ failed attempts → lockout ×10 per additional attempt (100, 1000, ...)
-- Lockouts are capped at 48 hours (2 days) — a phone number can never be
-- locked for longer, no matter how many consecutive failures occur.
--
-- Only the service-role edge function touches this table.

CREATE TABLE public.otp_lockouts (
  phone_number    VARCHAR(20) PRIMARY KEY,
  failed_attempts INT         NOT NULL DEFAULT 0,
  locked_until    TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_otp_lockouts_locked_until ON public.otp_lockouts(locked_until);

ALTER TABLE public.otp_lockouts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.otp_lockouts FROM anon, authenticated;