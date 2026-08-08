-- /supabase/migrations/00023_fix_linter_security.sql
-- Resolves Supabase database-linter findings (github: supabase/security-advisories
-- style checks surfaced by the Supabase "Database Linter").
--
-- 1) security_definer_view (lint 0010)
--    Plain views execute with the privileges of their creator (definer).
--    Setting security_invoker=true makes them run with the querying user's
--    privileges so Postgres RLS policies on the underlying tables are enforced.
-- 2) rls_disabled_in_public (lint 0013)
--    rate_limit_logs / password_reset_tokens are internal infrastructure tables
--    written only by edge functions using the service_role key (which bypasses
--    RLS). Enable RLS and revoke direct anon/authenticated access so PostgREST
--    cannot expose them.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Financial/schedule views must respect the caller's RLS context.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER VIEW v_loan_schedules  SET (security_invoker = true);
ALTER VIEW v_loan_financials SET (security_invoker = true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Internal infra tables: no direct client access.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE rate_limit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE password_reset_tokens ENABLE ROW LEVEL SECURITY;

-- service_role (edge functions) keeps its privileges via the superuser bypass;
-- anon/authenticated no longer have any access to these tables.
REVOKE ALL ON TABLE rate_limit_logs        FROM anon, authenticated;
REVOKE ALL ON TABLE password_reset_tokens  FROM anon, authenticated;

COMMIT;
