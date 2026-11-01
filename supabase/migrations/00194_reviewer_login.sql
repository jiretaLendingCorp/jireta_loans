-- =====================================================================
-- Jireta Loans & Credit Corp
-- Migration : 00194_reviewer_login.sql
-- Purpose   : Auth-log event types para sa Google Play reviewer sign-in.
--
-- Bakit:
--   Ang `auth-reviewer` edge function ay nagtatala ng Bawat reviewer login
--   (success at failure) sa `auth_logs` — iyon ang audit trail na hinihingi
--   para sa reviewer access. Ang `auth_logs.event_type` ay may CHECK
--   constraint, kaya kailangang idagdag ang dalawang bagong event bago
--   maging visible ang mga row. Best-effort ang writes sa function, kaya
--   HINDI humaharang ang login kahit hindi pa applied ito — pero walang
--   naipapasok na audit row.
--
-- Seguridad:
--   Walang reviewer credential, phone, o password na naka-store dito. Ang
--   configuration ay nasa Supabase Edge Function secrets lamang.
--   Idempotent: DROP + ADD ng constraint, safe i-rerun.
-- =====================================================================

BEGIN;

ALTER TABLE public.auth_logs
  DROP CONSTRAINT IF EXISTS auth_logs_event_type_check;

ALTER TABLE public.auth_logs
  ADD CONSTRAINT auth_logs_event_type_check CHECK (event_type IN (
    'login_success','login_fail','logout','otp_sent','otp_fail',
    'password_changed','account_locked','password_reset_requested',
    'session_expired','force_password_changed',
    'login_rate_limited','otp_rate_limited','password_reset_suspicious',
    'payment_attempt_blocked','suspicious_activity',
    -- 00194: Google Play reviewer access audit trail.
    'reviewer_login','reviewer_login_failed'
  ));

COMMENT ON COLUMN public.auth_logs.event_type IS
  'Auth event. reviewer_login / reviewer_login_failed = Google Play reviewer sign-in (see auth-reviewer Edge Function and 00194).';

COMMIT;
