-- ═══════════════════════════════════════════════════════════════════════════
-- Jireta Loans & Credit Corp 1966
-- Migration : 00007_fix_schema_grants.sql
-- Purpose   : Explicitly grant public-schema permissions to the PostgREST
--             roles (anon, authenticated, service_role).
--
-- WHY THIS IS NEEDED
-- ─────────────────────────────────────────────────────────────────────────
-- Newer Supabase projects (2024+) no longer auto-grant USAGE on the public
-- schema to the PostgREST roles. When auto_expose_new_tables is unset
-- (commented out in config.toml), every table/sequence must be explicitly
-- granted. Without these grants:
--
--   • getAdminClient() calls (service_role key) → "permission denied for
--     schema public" → PostgreSQL error code 42501 → Edge Function 401
--   • anon / authenticated client calls fail the same way.
--
-- This migration is IDEMPOTENT (GRANTs are no-ops if the privilege already
-- exists) and safe to run on both local and production instances.
--
-- HOW TO RUN
-- ─────────────────────────────────────────────────────────────────────────
-- Option A — Supabase Dashboard → SQL Editor: paste and run this file.
-- Option B — Supabase CLI: place this file in supabase/migrations/ and run
--             `supabase db push` (or `supabase db reset` locally).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. Schema-level USAGE ────────────────────────────────────────────────────
-- Required so PostgREST can resolve table names inside the schema.
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- ── 2. All existing tables ────────────────────────────────────────────────────
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL ROUTINES  IN SCHEMA public TO service_role;

-- anon and authenticated only need SELECT (RLS policies restrict further)
GRANT SELECT ON ALL TABLES    IN SCHEMA public TO anon, authenticated;
GRANT USAGE  ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;

-- ── 3. Default privileges (applies to tables created AFTER this migration) ───
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES    TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON ROUTINES  TO service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES    TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE  ON SEQUENCES TO anon, authenticated;

COMMIT;

-- ── Next step ─────────────────────────────────────────────────────────────────
-- After this runs successfully, execute 00006_bootstrap_head_manager.sql to
-- create the first head_manager account (if not already done).
-- ─────────────────────────────────────────────────────────────────────────────
