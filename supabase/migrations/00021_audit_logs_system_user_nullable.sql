-- supabase/migrations/00021_audit_logs_system_user_nullable.sql
--
-- Webhook callbacks (Xendit payments/disbursements) audit their work, but
-- they run without a logged-in user. Passing the placeholder 'system' violated
-- the NOT NULL FK to users(id), so every webhook audit write silently failed
-- (the helper swallows the error). Make performed_by nullable and represent
-- system-initiated actions as NULL.

ALTER TABLE public.audit_logs
  ALTER COLUMN performed_by DROP NOT NULL;