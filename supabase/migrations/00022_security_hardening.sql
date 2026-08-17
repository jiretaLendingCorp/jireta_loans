-- supabase/migrations/00022_security_hardening.sql
--
-- Abuse / suspicious-activity detection infrastructure.
--
--   security_blocks   — temporary blocks placed by rate-limit enforcement
--                       (login brute force, OTP spam, repeated payment
--                       attempts, password-reset flooding). Keyed rows with
--                       an expiry; consumed by _shared/rate_limiter.ts.
--
--   security_events   — append-only suspicious-activity trail for the head
--                       manager / audit. Records *why* a key was blocked.
--
-- Also widens auth_logs.event_type so rate-limit / block events can be
-- stored alongside the existing login_* events.

-- ─────────────────────────────────────────────────────────────────────
-- 1) security_blocks
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE public.security_blocks (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  key        TEXT        NOT NULL,
  reason     TEXT        NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_security_blocks_key       ON public.security_blocks(key);
CREATE INDEX idx_security_blocks_expires   ON public.security_blocks(expires_at);

-- ─────────────────────────────────────────────────────────────────────
-- 2) security_events
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE public.security_events (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_type VARCHAR(50) NOT NULL,
  key        TEXT        NOT NULL,
  user_id    UUID REFERENCES public.users(id) ON DELETE SET NULL,
  ip_address TEXT,
  detail     JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_security_events_type      ON public.security_events(event_type);
CREATE INDEX idx_security_events_key       ON public.security_events(key);
CREATE INDEX idx_security_events_user_id   ON public.security_events(user_id);
CREATE INDEX idx_security_events_created_at ON public.security_events(created_at);

-- ─────────────────────────────────────────────────────────────────────
-- 3) Widen auth_logs.event_type with abuse-detection events
-- ─────────────────────────────────────────────────────────────────────
ALTER TABLE public.auth_logs
  DROP CONSTRAINT IF EXISTS auth_logs_event_type_check;

ALTER TABLE public.auth_logs
  ADD CONSTRAINT auth_logs_event_type_check CHECK (event_type IN (
    'login_success','login_fail','logout','otp_sent','otp_fail',
    'password_changed','account_locked','password_reset_requested',
    'session_expired','force_password_changed',
    'login_rate_limited','otp_rate_limited','password_reset_suspicious',
    'payment_attempt_blocked','suspicious_activity'
  ));

-- ─────────────────────────────────────────────────────────────────────
-- 4) RLS: internal infra tables — no direct client access
-- ─────────────────────────────────────────────────────────────────────
ALTER TABLE public.security_blocks   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_events   ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.security_blocks  FROM anon, authenticated;
REVOKE ALL ON TABLE public.security_events  FROM anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 5) Maintenance — purge expired blocks and old event trail
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION cleanup_security_data()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM security_blocks WHERE expires_at < NOW();
  DELETE FROM security_events WHERE created_at < NOW() - INTERVAL '30 days';
END;
$$;