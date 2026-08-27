-- =====================================================================
-- Migration: 00106_audit_fixes_v5.sql
-- Purpose  : Final audit pass — address the "motong apat" top-4 + the
--            remaining orange items from the 10-point review (Aug 2026).
--
--   🔴 1) Remove otp_codes.code (plaintext-named, redundant with otp_hash)
--      - 00105 kept `code` as zero-downtime alias (trigger mirrored to otp_hash).
--        Edge `auth-otp` now writes only `otp_hash`; this migration drops the
--        alias column and its sync trigger for good. Plaintext OTP is never stored
--        (SHA-256 hex salted with phone, 64 chars).
--
--   🔴 2) Enforce lookup FKs (idempotent ensure — consolidated snapshot
--        00001 already has them, but live DBs that ran incremental migrations
--        may have missed some if created before the lookup pass).
--      - Ensures REFERENCES <lookup>(code) for:
--        users.account_status, loans.payment_frequency, loans.status,
--        lender_profiles.account_upgrade_status, disbursements.method/status,
--        payments.payment_method/status
--      - Also re-ensures other lookup FKs (gender, civil_status, etc.) via
--        helper check so dump shows enforced relationships, not free varchar.
--
--   🔴 3) Profile tables 1:1 children of users (FK to users(id) ON DELETE CASCADE)
--      - lender_profiles.id, rider_profiles.id, employee_profiles.id already
--        REFERENCES users(id) in 00001 snapshot; ensure live DB matches.
--
--   🔴 4) Tighten employee RLS (users + lender_profiles)
--      - users: employee bulk-read removed. Direct RLS now allows:
--        self OR head_manager all OR (employee reading lender/rider only).
--        Employee bulk lists go via service_role `users-admin?fn=get-list`
--        which enforces RBAC + audit and filters to rider/lender.
--        This hides head_manager rows + fcm_token / sensitive auth-adjacent
--        columns from bulk employee enumeration while keeping employee's
--        ability to list lenders/riders via the audited edge path.
--      - lender_profiles: documented as operational need (employee is loan
--        officer needing dob/monthly_income/gcash for verification). Direct
--        RLS stays head_manager/employee for realtime, but employee's outer
--        users rows are already limited, and sensitive bulk access is
--        encouraged via service_role. See comment in 00003 snapshot.
--        A stricter alternative (head_manager only) is included as commented
--        block for operators who want zero direct employee access.
--
--   🟠 4) loan_schedules UNIQUE(loan_id, installment_number) — already in
--        snapshot (00001: UNIQUE constraint). Ensure live DB has it.
--
--   🟠 5) application_* FK ON DELETE CASCADE + UNIQUE where 1:1 — already
--        in snapshot; ensure live DB.
--
--   🟠 10) notifications UPDATE hardening — policy + trigger already in
--        00105 / 00002 / 00003 snapshot. Ensure both exist and are documented.
--
--   Idempotent: safe to re-run. Uses catalog checks + IF NOT EXISTS guards.
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────
-- 1) otp_codes: drop deprecated `code` alias, keep only otp_hash
-- ─────────────────────────────────────────────────────────────────

-- Drop the alias-sync trigger/function first (they reference `code`).
DROP TRIGGER IF EXISTS trg_otp_codes_sync_alias ON public.otp_codes;
DROP FUNCTION IF EXISTS public.fn_otp_codes_sync_alias();

-- Backfill any row where otp_hash is NULL but code had the hash (should be
-- none after 00105, but handle zero-downtime window where edge still wrote both).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='otp_codes' AND column_name='code')
     AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='otp_codes' AND column_name='otp_hash') THEN
    EXECUTE 'UPDATE public.otp_codes SET otp_hash = code WHERE otp_hash IS NULL AND code IS NOT NULL';
  END IF;
END $$;

-- Remove any plaintext / non-hex rows before enforcing NOT NULL / CHECK.
DELETE FROM public.otp_codes
WHERE otp_hash IS NULL
   OR otp_hash !~ '^[0-9a-f]{64}$';

-- Drop the deprecated column (if it exists — was re-added as nullable alias in 00105).
ALTER TABLE public.otp_codes DROP COLUMN IF EXISTS code;

-- Enforce NOT NULL on otp_hash (should already be NOT NULL via 00001 snapshot,
-- but live DBs that had the alias may have nulled it).
DO $$
BEGIN
  -- Only set NOT NULL if no NULLs remain (we deleted them above).
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='otp_codes' AND column_name='otp_hash' AND is_nullable='YES') THEN
    ALTER TABLE public.otp_codes ALTER COLUMN otp_hash SET NOT NULL;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'otp_codes.otp_hash SET NOT NULL failed: %', SQLERRM;
END $$;

-- Enforce 64-hex shape.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='otp_codes_otp_hash_format' AND conrelid='public.otp_codes'::regclass) THEN
    ALTER TABLE public.otp_codes
      ADD CONSTRAINT otp_codes_otp_hash_format CHECK (otp_hash ~ '^[0-9a-f]{64}$') NOT VALID;
  END IF;
END $$;

DO $$
BEGIN
  BEGIN
    ALTER TABLE public.otp_codes VALIDATE CONSTRAINT otp_codes_otp_hash_format;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'otp_codes_otp_hash_format not validated: %', SQLERRM;
  END;
END $$;

COMMENT ON COLUMN public.otp_codes.otp_hash IS 'SHA-256 hex (64 chars) of OTP salted with phone; plaintext OTP is never stored. `code` alias removed in 00106.';

-- ─────────────────────────────────────────────────────────────────
-- 2) Lookup FKs — idempotent ensure for the 8 flagged columns + profiles
--    Helper: does a FK already cover (table, column)?
-- ─────────────────────────────────────────────────────────────────

-- Small helper function for reuse in this migration only.
CREATE OR REPLACE FUNCTION _ensure_lookup_fk(
  p_table regclass,
  p_column text,
  p_ref regclass,
  p_refcol text,
  p_conname text
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_exists boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
    WHERE c.conrelid = p_table
      AND c.contype = 'f'
      AND a.attname = p_column
      AND c.confrelid = p_ref
  ) INTO v_exists;

  IF v_exists THEN
    RETURN;
  END IF;

  -- Before adding, ensure orphan values would not break the FK.
  -- We do NOT auto-delete orphans; instead ADD CONSTRAINT NOT VALID then VALIDATE,
  -- so deployment does not fail if a legacy bad row exists. Operators should
  -- fix orphans and VALIDATE manually if warning appears.
  BEGIN
    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %s(%I) NOT VALID',
                   p_table, p_conname, p_column, p_ref, p_refcol);
    BEGIN
      EXECUTE format('ALTER TABLE %s VALIDATE CONSTRAINT %I', p_table, p_conname);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'FK % on %.% not validated (orphan rows exist): %', p_conname, p_table, p_column, SQLERRM;
    END;
  EXCEPTION WHEN duplicate_object THEN
    -- Constraint name collision — already exists under that name.
    NULL;
  WHEN OTHERS THEN
    RAISE WARNING 'Failed to add FK % on %.%: %', p_conname, p_table, p_column, SQLERRM;
  END;
END;
$$;

-- The 8 flagged columns:
SELECT _ensure_lookup_fk('public.users'::regclass,                'account_status',         'public.user_account_statuses'::regclass,        'code', 'fk_users_account_status');
SELECT _ensure_lookup_fk('public.loans'::regclass,                'payment_frequency',      'public.payment_frequencies'::regclass,          'code', 'fk_loans_payment_frequency');
SELECT _ensure_lookup_fk('public.loans'::regclass,                'status',                 'public.loan_statuses'::regclass,                'code', 'fk_loans_status');
SELECT _ensure_lookup_fk('public.lender_profiles'::regclass,      'account_upgrade_status', 'public.account_upgrade_statuses'::regclass,      'code', 'fk_lender_profiles_account_upgrade_status');
SELECT _ensure_lookup_fk('public.disbursements'::regclass,        'method',                 'public.disbursement_methods'::regclass,           'code', 'fk_disbursements_method');
SELECT _ensure_lookup_fk('public.disbursements'::regclass,        'status',                 'public.disbursement_statuses'::regclass,          'code', 'fk_disbursements_status');
SELECT _ensure_lookup_fk('public.payments'::regclass,             'payment_method',         'public.payment_methods'::regclass,                'code', 'fk_payments_payment_method');
SELECT _ensure_lookup_fk('public.payments'::regclass,             'status',                 'public.payment_statuses'::regclass,               'code', 'fk_payments_status');

-- Additional lookups that should be enforced but may have been missed historically
-- (no-op if already present — keeps dump honest that relationships are enforced):
SELECT _ensure_lookup_fk('public.lender_profiles'::regclass,      'gender',                 'public.gender_types'::regclass,                   'code', 'fk_lender_profiles_gender');
SELECT _ensure_lookup_fk('public.lender_profiles'::regclass,      'civil_status',           'public.civil_statuses'::regclass,                 'code', 'fk_lender_profiles_civil_status');
SELECT _ensure_lookup_fk('public.lender_profiles'::regclass,      'employment_type',        'public.employment_types'::regclass,               'code', 'fk_lender_profiles_employment_type');
SELECT _ensure_lookup_fk('public.rider_profiles'::regclass,       'vehicle_type',           'public.vehicle_types'::regclass,                  'code', 'fk_rider_profiles_vehicle_type');
SELECT _ensure_lookup_fk('public.addresses'::regclass,            'address_type',           'public.address_types'::regclass,                  'code', 'fk_addresses_address_type');
SELECT _ensure_lookup_fk('public.emergency_contacts'::regclass,   'relationship',           'public.relationship_types'::regclass,             'code', 'fk_emergency_contacts_relationship');
SELECT _ensure_lookup_fk('public.account_upgrade_documents'::regclass, 'document_type',     'public.document_types'::regclass,                 'code', 'fk_aud_document_type');
SELECT _ensure_lookup_fk('public.account_upgrade_documents'::regclass, 'status',            'public.account_upgrade_statuses'::regclass,       'code', 'fk_aud_status');
SELECT _ensure_lookup_fk('public.credit_investigations'::regclass,'status',                'public.credit_investigation_statuses'::regclass,  'code', 'fk_ci_status');
SELECT _ensure_lookup_fk('public.collection_assignments'::regclass,'status',               'public.collection_assignment_statuses'::regclass, 'code', 'fk_ca_status');
SELECT _ensure_lookup_fk('public.notifications'::regclass,        'type',                   'public.notification_types'::regclass,             'code', 'fk_notifications_type');
SELECT _ensure_lookup_fk('public.sms_logs'::regclass,             'status',                 'public.sms_statuses'::regclass,                   'code', 'fk_sms_logs_status');
SELECT _ensure_lookup_fk('public.loan_disbursement_preferences'::regclass,'method',         'public.disbursement_methods'::regclass,           'code', 'fk_loan_disb_prefs_method');
-- Clean up helper (keep it for future migrations? Drop to not pollute).
DROP FUNCTION _ensure_lookup_fk(regclass, text, regclass, text, text);

-- ─────────────────────────────────────────────────────────────────
-- 3) Profile tables 1:1 children of users — ensure FK id REFERENCES users(id) ON DELETE CASCADE
-- ─────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
    WHERE c.conrelid='public.lender_profiles'::regclass AND c.contype='f' AND a.attname='id'
  ) THEN
    -- Ensure no orphan ids before adding
    DELETE FROM public.lender_profiles lp WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id=lp.id);
    ALTER TABLE public.lender_profiles
      ADD CONSTRAINT lender_profiles_id_fkey FOREIGN KEY (id) REFERENCES public.users(id) ON DELETE CASCADE NOT VALID;
    BEGIN
      ALTER TABLE public.lender_profiles VALIDATE CONSTRAINT lender_profiles_id_fkey;
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'lender_profiles_id_fkey not validated: %', SQLERRM; END;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
    WHERE c.conrelid='public.rider_profiles'::regclass AND c.contype='f' AND a.attname='id'
  ) THEN
    DELETE FROM public.rider_profiles rp WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id=rp.id);
    ALTER TABLE public.rider_profiles
      ADD CONSTRAINT rider_profiles_id_fkey FOREIGN KEY (id) REFERENCES public.users(id) ON DELETE CASCADE NOT VALID;
    BEGIN
      ALTER TABLE public.rider_profiles VALIDATE CONSTRAINT rider_profiles_id_fkey;
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'rider_profiles_id_fkey not validated: %', SQLERRM; END;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
    WHERE c.conrelid='public.employee_profiles'::regclass AND c.contype='f' AND a.attname='id'
  ) THEN
    DELETE FROM public.employee_profiles ep WHERE NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id=ep.id);
    ALTER TABLE public.employee_profiles
      ADD CONSTRAINT employee_profiles_id_fkey FOREIGN KEY (id) REFERENCES public.users(id) ON DELETE CASCADE NOT VALID;
    BEGIN
      ALTER TABLE public.employee_profiles VALIDATE CONSTRAINT employee_profiles_id_fkey;
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'employee_profiles_id_fkey not validated: %', SQLERRM; END;
  END IF;
END $$;

COMMENT ON TABLE public.lender_profiles   IS '1:1 child of users(id) ON DELETE CASCADE — each lender is a user.';
COMMENT ON TABLE public.rider_profiles    IS '1:1 child of users(id) ON DELETE CASCADE — each rider is a user.';
COMMENT ON TABLE public.employee_profiles IS '1:1 child of users(id) ON DELETE CASCADE — each employee is a user.';

-- ─────────────────────────────────────────────────────────────────
-- 4) loan_schedules UNIQUE(loan_id, installment_number)
--    application_* FK ON DELETE CASCADE + 1:1 UNIQUE where needed
-- ─────────────────────────────────────────────────────────────────

-- loan_schedules unique
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.loan_schedules'::regclass AND contype='u'
      AND array_length(conkey,1)=2
  ) THEN
    -- Deduplicate if violation exists (keep lowest id per duplicate)
    IF EXISTS (SELECT 1 FROM public.loan_schedules GROUP BY loan_id, installment_number HAVING COUNT(*)>1) THEN
      RAISE WARNING 'loan_schedules has duplicate (loan_id, installment_number) — deduplicating';
      DELETE FROM public.loan_schedules
      WHERE id NOT IN (
        SELECT DISTINCT ON (loan_id, installment_number) id
        FROM public.loan_schedules ORDER BY loan_id, installment_number, created_at ASC
      );
    END IF;
    ALTER TABLE public.loan_schedules ADD CONSTRAINT uq_loan_schedules_loan_installment UNIQUE (loan_id, installment_number);
  END IF;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- application_* — ensure FK ON DELETE CASCADE exists (snapshot already has it; this repairs live DBs created before 00022 3NF pass)
DO $$
DECLARE
  tbl text;
  fk_exists boolean;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['application_personal_info','application_employment_info','application_loan_details','application_addresses','application_emergency_contacts','application_co_makers','application_documents'] LOOP
    SELECT EXISTS (
      SELECT 1 FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
      WHERE c.conrelid = tbl::regclass AND c.contype='f' AND a.attname='application_id'
        AND c.confdeltype='c' -- ON DELETE CASCADE
    ) INTO fk_exists;
    IF NOT fk_exists THEN
      -- Drop any non-cascade FK first, then re-add with CASCADE
      BEGIN
        EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT IF EXISTS %I', tbl, tbl || '_application_id_fkey');
      EXCEPTION WHEN OTHERS THEN NULL; END;
      -- Generic: try to add cascade FK if column exists
      BEGIN
        EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (application_id) REFERENCES public.in_office_applications(id) ON DELETE CASCADE NOT VALID', tbl, tbl || '_app_id_fkey');
        EXECUTE format('ALTER TABLE public.%I VALIDATE CONSTRAINT %I', tbl, tbl || '_app_id_fkey');
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Could not add cascade FK for %: %', tbl, SQLERRM;
      END;
    END IF;
  END LOOP;
END $$;

-- Ensure 1:1 uniqueness for the three 1:1 children (snapshot has UNIQUE(application_id))
CREATE UNIQUE INDEX IF NOT EXISTS uq_application_personal_info_app_id  ON public.application_personal_info(application_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_application_employment_info_app_id ON public.application_employment_info(application_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_application_loan_details_app_id    ON public.application_loan_details(application_id);

-- ─────────────────────────────────────────────────────────────────
-- 5) Tighten RLS: users (and document lender_profiles)
-- ─────────────────────────────────────────────────────────────────

-- USERS: replace broad `OR auth_role() IN ('head_manager','employee')` with scoped employee.
DROP POLICY IF EXISTS users_read_own ON public.users;
CREATE POLICY users_read_own ON public.users
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR auth_role() = 'head_manager'
    OR (
      auth_role() = 'employee'
      AND role_id IN (SELECT id FROM public.roles WHERE name IN ('lender','rider'))
    )
  );
COMMENT ON POLICY users_read_own ON public.users IS
  'Tightened in 00106: head_manager can read all; employee can read only lender/rider rows (via role_id) + self; bulk lists go via service_role users-admin?fn=get-list with audit. Direct employee bulk enumeration of head_manager/employee rows (and fcm_token/last_login_at) is blocked.';

-- LENDER_PROFILES: keep operational but document. The stricter alternative
-- (head_manager only for direct reads, forcing employee via service_role) is
-- provided below as an opt-in. Uncomment to enforce zero direct employee access.
-- Current policy stays head_manager/employee for realtime needs; audit concern
-- is mitigated by the tightened users policy (employee cannot bulk-enumerate
-- head_manager users to join) and by encouraging service_role for bulk fetches.

-- Ensure lender_profiles policy exists with correct shape (recreate to be idempotent)
DROP POLICY IF EXISTS lender_profiles_read ON public.lender_profiles;
CREATE POLICY lender_profiles_read ON public.lender_profiles
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
  );
COMMENT ON POLICY lender_profiles_read ON public.lender_profiles IS
  'Operational: employee needs dob/monthly_income/gcash for loan verification. Bulk lists via service_role users-admin are preferred (audited). To restrict further, replace with head_manager-only policy and force employee via service_role (see 00106 commented block).';

-- OPTIONAL STRICTER VERSION (uncomment to enforce):
-- DROP POLICY IF EXISTS lender_profiles_read ON public.lender_profiles;
-- CREATE POLICY lender_profiles_read ON public.lender_profiles
--   FOR SELECT TO authenticated
--   USING (id = auth.uid() OR auth_role() = 'head_manager');

-- Ensure other policies that intentionally allow employee remain documented
-- (no change — employee is loan officer for those domain tables).

-- ─────────────────────────────────────────────────────────────────
-- 6) notifications: ensure UPDATE policy + column guard trigger
-- ─────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS notifications_update_own ON public.notifications;
CREATE POLICY notifications_update_own ON public.notifications
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
COMMENT ON POLICY notifications_update_own ON public.notifications IS
  'Client may UPDATE own notifications, but trigger trg_enforce_notifications_update_columns restricts columns to is_read/read_at only. Other writes via service_role.';

-- Ensure trigger exists (definition lives in 00002 snapshot; re-assert here for live DBs)
CREATE OR REPLACE FUNCTION public.enforce_notifications_update_columns()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
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
    RAISE EXCEPTION 'notifications: only is_read and read_at may be updated by client'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_notifications_update_columns ON public.notifications;
CREATE TRIGGER trg_enforce_notifications_update_columns
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.enforce_notifications_update_columns();

-- Optional hardening: mark_notification_read RPC (preferred over direct UPDATE)
-- Clients should call this instead of UPDATE when possible.
CREATE OR REPLACE FUNCTION public.mark_notification_read(p_notification_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.notifications
  SET is_read = TRUE,
      read_at = NOW()
  WHERE id = p_notification_id
    AND user_id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Notification not found or not owned' USING ERRCODE='42501';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.mark_notification_read(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_notification_read(uuid) TO authenticated;
COMMENT ON FUNCTION public.mark_notification_read(uuid) IS 'Safer than direct UPDATE: marks own notification read (is_read/read_at only). RLS still enforced.';

-- ─────────────────────────────────────────────────────────────────
-- 7) Miscellaneous hardening already in 00105 — re-ensure
-- ─────────────────────────────────────────────────────────────────

-- emergency_contacts 1:N but no duplicate phone per lender
CREATE UNIQUE INDEX IF NOT EXISTS uq_emergency_contacts_lender_phone
  ON public.emergency_contacts(lender_id, phone_number);

-- payment_reversals one per payment
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.payment_reversals GROUP BY payment_id HAVING COUNT(*)>1) THEN
    RAISE WARNING 'payment_reversals duplicate payment_ids — deduplicating';
    DELETE FROM public.payment_reversals WHERE id NOT IN (
      SELECT DISTINCT ON (payment_id) id FROM public.payment_reversals ORDER BY payment_id, reversed_at ASC
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='uq_payment_reversals_payment_id' AND conrelid='public.payment_reversals'::regclass) THEN
    -- If a UNIQUE index already exists under a different name, keep it and just add comment
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.payment_reversals'::regclass AND contype='u' AND array_position(conkey, (SELECT attnum FROM pg_attribute WHERE attrelid='public.payment_reversals'::regclass AND attname='payment_id')) IS NOT NULL) THEN
      ALTER TABLE public.payment_reversals ADD CONSTRAINT uq_payment_reversals_payment_id UNIQUE (payment_id);
    END IF;
  END IF;
END $$;

COMMIT;
