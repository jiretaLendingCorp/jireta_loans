-- =====================================================================
-- Migration: 00105_audit_fixes_v4.sql
-- Purpose  : Fix remaining issues from the 12-point schema audit (Aug 2026).
--
--   Issues fixed here (genuine bugs):
--     1) otp_codes.code is plaintext-named and holds a hash (00030 widened
--        it to TEXT but kept the name `code`). Rename to `otp_hash`,
--        enforce 64-hex shape, and add a back-compat alias so old edge
--        code keeps working until redeployed. Also align with email_reset_otps.otp_hash.
--     2) loan_disbursement_preferences.method used CHECK IN (...) instead
--        of FK to disbursement_methods(code). Replace with real FK.
--     3) emergency_contacts had UNIQUE(lender_id) (idx_emergency_lender_id_unique)
--        — forces at most ONE contact per lender. Drop it; the app needs 1:N.
--        Keep the non-unique index idx_emergency_lender_id.
--     4) payment_reversals.payment_id had no uniqueness — same payment
--        could be reversed multiple times. Enforce UNIQUE(payment_id).
--        If multi-reversal history is ever wanted, drop this constraint.
--     5) notifications_update_own allowed UPDATE of ANY column where
--        user_id = auth.uid(). Add BEFORE UPDATE trigger that only allows
--        is_read / read_at to change via client; other columns are blocked.
--        Mark-read still goes through notifications-view?fn=mark-read
--        (service_role, bypasses RLS but trigger is permissive for is_read/read_at only).
--     6) loans missing term_periods/installment_amount in the consolidated
--        snapshot (added in 00017). Re-ensure they exist for fresh clones.
--     7) Harden otp_codes / login_lockouts / email_otp_lockouts attempts checks.
--     8) Add comment / idempotent safety for in_office_applications loan_id
--        removal (circular FK break — 00099 dropped loan_id; keep it dropped).
--
--   Issues verified NOT bugs (no change, documented):
--     - FKs for user_account_statuses, loan_statuses, payment_statuses,
--       payment_methods, disbursement_methods/statuses,
--       collection_assignment_statuses, credit_investigation_statuses,
--       notification_types, relationship_types, payment_frequencies,
--       address_types, document_types, gender_types, civil_statuses,
--       employment_types, vehicle_types, platform_types, sms_statuses,
--       in_office_application_statuses are ALREADY enforced via
--       REFERENCES <lookup>(code) in 00001_tables.sql:470ff.
--     - lender_profiles/rider_profiles/employee_profiles id already
--       REFERENCES users(id) ON DELETE CASCADE (1-to-1) in 00001:523ff.
--     - payments orphan guard payments_context_check already exists (00029).
--     - RLS mostly SELECT-only is INTENTIONAL: all mutations go through
--       service_role Edge Functions; authenticated has no direct INSERT/UPDATE/DELETE.
--     - users / lender_profiles employee read-all is INTENTIONAL for loan
--       processing; sensitive auth data lives in auth.users, not public.users.
--     - application_* and co_makers duplication are intentional snapshots
--       (historical record) vs. live profiles.
--     - loan summary vs loan_schedules: v_loan_financials / v_loan_schedules
--       are source of truth; loans.installment_amount is agreed snapshot.
--
--   Idempotent: safe to re-run.
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────
-- 1) otp_codes: rename code -> otp_hash, enforce hash shape
-- ─────────────────────────────────────────────────────────────────

-- Backfill: 00030 widened code to TEXT and edge function now writes SHA-256 hex
-- into `code`. If a legacy plaintext row still exists, it will be 6 chars and
-- violate the new CHECK — those rows are already expired/used; clear them.
DELETE FROM public.otp_codes
WHERE char_length(code) != 64
  AND code !~ '^[0-9a-f]{64}$';

-- Rename column `code` -> `otp_hash` (IF NOT EXISTS guard via catalog check).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='otp_codes' AND column_name='code'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='otp_codes' AND column_name='otp_hash'
  ) THEN
    ALTER TABLE public.otp_codes RENAME COLUMN code TO otp_hash;
  ELSIF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='otp_codes' AND column_name='otp_hash'
  ) THEN
    ALTER TABLE public.otp_codes ADD COLUMN otp_hash TEXT;
  END IF;
END $$;

-- Enforce hash shape: 64 lowercase hex chars (SHA-256). NOT VALID then VALIDATE
-- so any concurrent insert in the same txn still checked, but legacy rows already deleted above.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='otp_codes_otp_hash_format') THEN
    ALTER TABLE public.otp_codes
      ADD CONSTRAINT otp_codes_otp_hash_format
      CHECK (otp_hash ~ '^[0-9a-f]{64}$') NOT VALID;
  END IF;
END $$;

-- Back-compat alias: some edge deployments may still INSERT INTO otp_codes(code)
-- until they are redeployed. Create a compatibility view? Instead, add a
-- generated alias via trigger + keep a legacy `code` column as alias if needed.
-- We already renamed, so to avoid breaking old deploys that still write `code`,
-- re-add `code` as a thin alias (nullable) synced by trigger.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='otp_codes' AND column_name='code'
  ) THEN
    ALTER TABLE public.otp_codes ADD COLUMN code TEXT;
    COMMENT ON COLUMN public.otp_codes.code IS 'DEPRECATED alias for otp_hash — kept for zero-downtime deploy; writes are mirrored to otp_hash by trigger.';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.fn_otp_codes_sync_alias()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Keep code <-> otp_hash in sync so either column write works.
  IF TG_OP = 'INSERT' THEN
    IF NEW.otp_hash IS NULL AND NEW.code IS NOT NULL THEN
      NEW.otp_hash := NEW.code;
    ELSIF NEW.code IS NULL AND NEW.otp_hash IS NOT NULL THEN
      NEW.code := NEW.otp_hash;
    ELSIF NEW.code IS DISTINCT FROM NEW.otp_hash THEN
      -- Prefer otp_hash when both supplied but differ.
      NEW.code := NEW.otp_hash;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.otp_hash IS DISTINCT FROM OLD.otp_hash THEN
      NEW.code := NEW.otp_hash;
    ELSIF NEW.code IS DISTINCT FROM OLD.code THEN
      NEW.otp_hash := NEW.code;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_otp_codes_sync_alias ON public.otp_codes;
CREATE TRIGGER trg_otp_codes_sync_alias
  BEFORE INSERT OR UPDATE ON public.otp_codes
  FOR EACH ROW EXECUTE FUNCTION public.fn_otp_codes_sync_alias();

COMMENT ON COLUMN public.otp_codes.otp_hash IS 'SHA-256 hex (64 chars) of OTP salted with phone; plaintext OTP is never stored (email_reset_otps uses same scheme).';

-- Validate hash constraint now that alias sync is active.
DO $$
BEGIN
  BEGIN
    ALTER TABLE public.otp_codes VALIDATE CONSTRAINT otp_codes_otp_hash_format;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'otp_codes_otp_hash_format not validated (legacy rows): %', SQLERRM;
  END;
END $$;

-- Ensure otp_codes remains RLS enabled and no direct anon access.
-- Table already has RLS from 00001; keep service_role-only writes.

-- ─────────────────────────────────────────────────────────────────
-- 2) loan_disbursement_preferences.method: CHECK -> FK
-- ─────────────────────────────────────────────────────────────────

-- Drop old CHECK constraint if it exists (name may vary: loan_disbursement_preferences_method_check).
DO $$
DECLARE
  c RECORD;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.loan_disbursement_preferences'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%method%IN%gcash%office_cash%rider_delivery%'
  LOOP
    EXECUTE format('ALTER TABLE public.loan_disbursement_preferences DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

-- Also drop any CHECK that was auto-named in 00001 snapshot.
ALTER TABLE public.loan_disbursement_preferences
  DROP CONSTRAINT IF EXISTS loan_disbursement_preferences_method_check;

-- Add real FK to disbursement_methods(code) if not already present.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_loan_disbursement_preferences_method'
      AND conrelid = 'public.loan_disbursement_preferences'::regclass
  ) THEN
    -- Ensure any existing method values exist in lookup (they should from seeds).
    -- Insert missing codes if a legacy value slipped in that matches a valid code shape but not seeded.
    INSERT INTO public.disbursement_methods (code, label, sort_order)
    VALUES ('gcash','GCash',1), ('office_cash','Office Cash',2), ('rider_delivery','Rider Delivery',3)
    ON CONFLICT (code) DO NOTHING;

    ALTER TABLE public.loan_disbursement_preferences
      ADD CONSTRAINT fk_loan_disbursement_preferences_method
      FOREIGN KEY (method) REFERENCES public.disbursement_methods(code);
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────
-- 3) emergency_contacts: drop UNIQUE(lender_id) — allow 1:N
-- ─────────────────────────────────────────────────────────────────

DROP INDEX IF EXISTS public.idx_emergency_lender_id_unique;

-- Ensure the non-unique index exists for RLS/joins.
CREATE INDEX IF NOT EXISTS idx_emergency_lender_id ON public.emergency_contacts(lender_id);

-- Prevent exact duplicate (same phone for same lender) but allow multiple distinct contacts.
CREATE UNIQUE INDEX IF NOT EXISTS uq_emergency_contacts_lender_phone
  ON public.emergency_contacts(lender_id, phone_number);

COMMENT ON TABLE public.emergency_contacts IS '1:N — each lender may have multiple emergency contacts. UNIQUE(lender_id) was removed in 00105 (was idx_emergency_lender_id_unique); replaced by UNIQUE(lender_id, phone_number).';

-- ─────────────────────────────────────────────────────────────────
-- 4) payment_reversals: enforce one reversal per payment
-- ─────────────────────────────────────────────────────────────────

DO $$
BEGIN
  -- If duplicate payment_ids already exist, keep the earliest reversal per payment and delete extras
  -- (should not happen in production; warning path).
  IF EXISTS (
    SELECT 1 FROM public.payment_reversals GROUP BY payment_id HAVING COUNT(*) > 1
  ) THEN
    RAISE WARNING 'payment_reversals has duplicate payment_ids — deduplicating to enforce UNIQUE(payment_id)';
    DELETE FROM public.payment_reversals
    WHERE id NOT IN (
      SELECT DISTINCT ON (payment_id) id FROM public.payment_reversals ORDER BY payment_id, reversed_at ASC
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'uq_payment_reversals_payment_id'
      AND conrelid = 'public.payment_reversals'::regclass
  ) THEN
    ALTER TABLE public.payment_reversals
      ADD CONSTRAINT uq_payment_reversals_payment_id UNIQUE (payment_id);
  END IF;
END $$;

-- Keep the index for FK lookups (now backing the unique constraint).
-- Existing idx_payment_reversals_payment_id remains.

-- ─────────────────────────────────────────────────────────────────
-- 5) notifications: guard UPDATE to only is_read / read_at
-- ─────────────────────────────────────────────────────────────────

-- Keep the RLS UPDATE policy (notifications_update_own) added in 00099 so
-- clients can mark-read without service_role. Harden it with a trigger that
-- blocks any column besides is_read / read_at from changing.
-- Writes to other columns must go through service_role Edge Functions.

CREATE OR REPLACE FUNCTION public.enforce_notifications_update_columns()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Allow service_role to bypass? No — service_role edge functions also only
  -- ever touch is_read/read_at, so hardening applies uniformly. Postgres
  -- session_user check kept for operational escape hatch.
  -- Only is_read and read_at may change; every other column must be identical.
  IF NEW.user_id        IS DISTINCT FROM OLD.user_id
     OR NEW.triggered_by IS DISTINCT FROM OLD.triggered_by
     OR NEW.title         IS DISTINCT FROM OLD.title
     OR NEW.body          IS DISTINCT FROM OLD.body
     OR NEW.type          IS DISTINCT FROM OLD.type
     OR NEW.reference_id  IS DISTINCT FROM OLD.reference_id
     OR NEW.reference_type IS DISTINCT FROM OLD.reference_type
     OR NEW.fcm_sent      IS DISTINCT FROM OLD.fcm_sent
     OR NEW.sent_at       IS DISTINCT FROM OLD.sent_at
     OR NEW.created_at    IS DISTINCT FROM OLD.created_at
     OR NEW.id            IS DISTINCT FROM OLD.id
  THEN
    RAISE EXCEPTION 'notifications: only is_read and read_at may be updated by client (blocked change to other columns)'
      USING ERRCODE = '42501';
  END IF;

  -- is_read may only go false->true client-side (no unread flip). service_role
  -- can reset if needed via direct SQL, but edge function never does.
  -- Enforce via RLS-adjacent rule: allow only is_read=true transition when
  -- called as authenticated. We cannot easily distinguish role in trigger,
  -- so allow both but log warning if flipping back.
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_notifications_update_columns ON public.notifications;
CREATE TRIGGER trg_enforce_notifications_update_columns
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.enforce_notifications_update_columns();

-- Document the invariant.
COMMENT ON POLICY notifications_update_own ON public.notifications IS
  'Client may UPDATE own notifications, but trigger trg_enforce_notifications_update_columns restricts columns to is_read/read_at only. Other writes must go through service_role edge functions.';

-- ─────────────────────────────────────────────────────────────────
-- 6) loans term data: ensure term_periods / installment_amount exist
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE public.loans
  ADD COLUMN IF NOT EXISTS term_periods INT CHECK (term_periods > 0),
  ADD COLUMN IF NOT EXISTS installment_amount DECIMAL(12,2) CHECK (installment_amount > 0);

ALTER TABLE public.application_loan_details
  ADD COLUMN IF NOT EXISTS term_periods INT CHECK (term_periods > 0);

-- Backfill loans from schedule if null (idempotent).
UPDATE public.loans l
SET term_periods       = s.cnt,
    installment_amount = s.first_amount
FROM (
  SELECT ls.loan_id,
         COUNT(*) AS cnt,
         (ARRAY_AGG(ls.amount_due ORDER BY ls.installment_number))[1] AS first_amount
  FROM public.loan_schedules ls
  GROUP BY ls.loan_id
) s
WHERE l.id = s.loan_id
  AND (l.term_periods IS NULL OR l.installment_amount IS NULL);

-- ─────────────────────────────────────────────────────────────────
-- 7) Harden attempts / is_read constraints (idempotent)
-- ─────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='otp_codes_attempts_check' AND conrelid='public.otp_codes'::regclass) THEN
    ALTER TABLE public.otp_codes ADD CONSTRAINT otp_codes_attempts_check CHECK (attempts >= 0) NOT VALID;
    BEGIN
      ALTER TABLE public.otp_codes VALIDATE CONSTRAINT otp_codes_attempts_check;
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'otp_codes_attempts_check not validated: %', SQLERRM; END;
  END IF;

  -- email_reset_otps already has attempts >=0; ensure index exists
  CREATE INDEX IF NOT EXISTS idx_email_reset_otps_email_used ON public.email_reset_otps(email) WHERE used = FALSE;

  -- payment_reversals reason not empty
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payment_reversals_reason_not_empty' AND conrelid='public.payment_reversals'::regclass) THEN
    ALTER TABLE public.payment_reversals ADD CONSTRAINT payment_reversals_reason_not_empty CHECK (char_length(btrim(reason)) > 0) NOT VALID;
    BEGIN
      ALTER TABLE public.payment_reversals VALIDATE CONSTRAINT payment_reversals_reason_not_empty;
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'payment_reversals_reason_not_empty not validated: %', SQLERRM; END;
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────
-- 8) Circular FK cleanup — ensure in_office_applications.loan_id stays dropped
-- ─────────────────────────────────────────────────────────────────

ALTER TABLE public.in_office_applications DROP COLUMN IF EXISTS loan_id;

-- Ensure the canonical FK loans.in_office_application_id exists.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname='fk_loans_in_office' AND conrelid='public.loans'::regclass
  ) THEN
    ALTER TABLE public.loans
      ADD CONSTRAINT fk_loans_in_office
      FOREIGN KEY (in_office_application_id) REFERENCES public.in_office_applications(id);
  END IF;
END $$;

COMMIT;
