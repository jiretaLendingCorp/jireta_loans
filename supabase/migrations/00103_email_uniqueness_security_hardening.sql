-- supabase/migrations/00103_email_uniqueness_security_hardening.sql
-- Purpose : Email Uniqueness Validation — defense-in-depth security hardening.
--
-- Background
--   `users.email` already has a UNIQUE constraint, but PostgreSQL's UNIQUE is
--   case-SENSITIVE ( `Admin@Example.com` ≠ `admin@example.com` ).  Every Edge
--   Function lower-cases the address (`…trim().toLowerCase()`) before storage,
--   so the invariant is SUPPOSED to be "lower(email) is unique".  Without a
--   DB-level guarantee the invariant can be violated by:
--     • legacy rows mixed-case before the lower-casing convention,
--     • a direct SQL insertion / migration,
--     • a TOCTOU race between the pre-insert SELECT and the INSERT.
--
--   A duplicated email is a security issue: account enumeration, credential
--   stuffing, GoTrue / PostgREST confusion, and policy-level identity
--   leaks.  This migration enforces the invariant at the lowest layer.
--
-- Changes
--   1) Normalisation trigger  `fn_users_normalize_email`
--      — BEFORE INSERT OR UPDATE OF email on users
--      — trims surrounding whitespace and lower-cases the value so every
--        stored email is canonical.  NULL is preserved (riders/lenders have
--        no email — see trg_users_rider_lender_no_email which already NULLs
--        synthetic jireta.temp addresses).
--   2) Case-insensitive partial unique index  `uq_users_email_lower`
--      — ON users (lower(email)) WHERE email IS NOT NULL
--      — Makes lower(email) uniqueness enforceable even under concurrent
--        inserts (the index violation is atomic).  IF NOT EXISTS so the
--        migration is idempotent.
--   3) Backfill — canonicalise any existing legacy rows with upper-case
--      letters or surrounding spaces so the new index can be created without
--      a pre-existing violation breaking deployment.
BEGIN;

SET search_path = public, extensions;

-- ── 1) Backfill legacy rows ───────────────────────────────────────────────
-- Trim + lower every non-null email that is not already canonical.
-- The WHERE narrows the update to rows that actually need it to avoid a
-- table-wide rewrite on large deployments.
UPDATE public.users
SET email = lower(trim(email))
WHERE email IS NOT NULL
  AND email <> lower(trim(email));

-- ── 2) Normalisation trigger ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_users_normalize_email()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.email IS NOT NULL THEN
    -- Use btrim to mirror Dart's .trim() (spaces, tabs, newlines).
    NEW.email := lower(btrim(NEW.email));
    -- Treat empty string as NULL so the users_email_or_phone CHECK stays valid
    -- and the partial unique index is not polluted by '' duplicates.
    IF NEW.email = '' THEN
      NEW.email := NULL;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_normalize_email ON users;
CREATE TRIGGER trg_users_normalize_email
  BEFORE INSERT OR UPDATE OF email ON users
  FOR EACH ROW EXECUTE FUNCTION fn_users_normalize_email();

-- ── 3) Case-insensitive partial unique index ──────────────────────────────
-- lower(email) is already canonical due to the trigger, but the expression
-- index guarantees the DB still rejects a concurrent race even if the trigger
-- were somehow bypassed.  Partial WHERE email IS NOT NULL preserves the
-- Postgres semantics for riders/lenders (many NULL emails are allowed).
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email_lower
  ON public.users (lower(email))
  WHERE email IS NOT NULL;

-- Document the invariant for future operators (\d users).
COMMENT ON INDEX uq_users_email_lower IS
  'Security: case-insensitive Email Uniqueness Check — lower(email) must be unique where email IS NOT NULL.';

COMMIT;
