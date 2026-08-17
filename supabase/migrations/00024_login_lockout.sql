-- supabase/migrations/00024_login_lockout.sql
--
-- Persistent, escalating web-login lockout (email/password — head manager and
-- employees). Mirrors the OTP lockout so both login paths share the same
-- product spec:
--   3 failed attempts  → 3 minutes
--   4 failed attempts  → 10 minutes
--   5+ failed attempts → lockout ×10 per additional attempt (100, 1000, ...)
--   Lockouts are capped at 48 hours (2 days) — an account can never be locked
--   for longer, no matter how many consecutive failures occur.
--
-- Stored server-side per user, so closing the web app / restarting the browser
-- can NOT reset the count. Only a successful login (or waiting out the lock)
-- clears it.

CREATE TABLE public.login_lockouts (
  user_id         UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  failed_attempts INT         NOT NULL DEFAULT 0,
  locked_until    TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_login_lockouts_locked_until ON public.login_lockouts(locked_until);

ALTER TABLE public.login_lockouts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.login_lockouts FROM anon, authenticated;