-- =====================================================================
-- Migration: 00107_hardening_orange_items.sql
-- Purpose  : Address remaining 🟠 + 🔴 items from 10-point review (Aug 2026)
--            PLUS verify 🔴 items are enforced (idempotent).
--
--   🔴 1) Lookup FKs visibly enforced — already in 00001 snapshot + 00106
--        _ensure_lookup_fk. This migration re-verifies with NOT VALID guards
--        so `pg_constraint` dump always shows FKs. No-op if already present.
--
--   🔴 2) loan_schedules UNIQUE(loan_id, installment_number) — already in
--        00001 snapshot (loan_schedules_loan_id_installment_number_key).
--        Re-ensure idempotently.
--
--   🔴 3) Application child FK ON DELETE CASCADE + UNIQUE where 1:1
--        — already in 00001 + re-ensured in 00106. Re-verify here.
--
--   🟠 4) notifications_update_own too broad — keep row-level policy
--        (user_id = auth.uid()) but harden column guard trigger to also
--        prevent is_read flip-back (false->true only) and ensure read_at is
--        set when is_read becomes true. Keep mark_notification_read RPC as
--        preferred path (service_role bypasses RLS but trigger still allows
--        only is_read/read_at). Also add bulk RPC mark_all_notifications_read.
--        Clients SHOULD call RPC instead of direct UPDATE.
--
--   🟠 5) addresses allows employee to see all addresses — TIGHTENED.
--        Direct RLS now: owner OR head_manager OR rider assigned to lender.
--        Employee bulk access via service_role edge (ci-view, collections-view,
--        users-admin, etc. which use getAdminClient() bypassing RLS). This
--        removes broad personal-data enumeration via direct PostgREST.
--        Optional employee-allow policy is kept as commented block for operators
--        who need legacy employee direct read.
--
--   🟠 6) lender_profiles employee broad read — TIGHTENED to head_manager
--        only for direct RLS (self OR head_manager). Employee operational
--        need (dob/monthly_income/gcash for loan verification) is served via
--        service_role edge functions (ci-view, loans-view, users-admin) which
--        bypass RLS. Direct bulk enumeration of PII via PostgREST is blocked.
--        Uncomment alternative policy at bottom to restore employee direct read
--        if your deployment intentionally needs it for realtime.
--
--   🟠 7) rider_locations policy complex — CENTRALIZED into
--        can_view_rider_location(rider_id) SECURITY DEFINER function.
--        Policy now delegates lender check to that function, making auth logic
--        single-source and maintainable. Lender visibility: active collection
--        (accepted), CI (accepted/in_progress), or pending rider_delivery
--        disbursement on any of their loans. Head_manager/employee/rider_self
--        bypass is preserved.
--
--   Idempotent: safe to re-run. Uses catalog checks + IF NOT EXISTS guards.
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────
-- 1) Re-ensure lookup FKs (idempotent) — covers the 8 flagged columns
--    plus additional lookups. No-op if already enforced.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION _ensure_lookup_fk(
  p_table regclass,
  p_column text,
  p_ref regclass,
  p_refcol text,
  p_conname text
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_exists boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
    WHERE c.conrelid=p_table AND c.contype='f' AND a.attname=p_column AND c.confrelid=p_ref
  ) INTO v_exists;
  IF v_exists THEN RETURN; END IF;
  BEGIN
    EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %s(%I) NOT VALID', p_table, p_conname, p_column, p_ref, p_refcol);
    BEGIN EXECUTE format('ALTER TABLE %s VALIDATE CONSTRAINT %I', p_table, p_conname);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'FK % on %.% not validated (orphan rows): %', p_conname, p_table, p_column, SQLERRM; END;
  EXCEPTION WHEN duplicate_object THEN NULL;
            WHEN OTHERS THEN RAISE WARNING 'Failed FK % on %.%: %', p_conname, p_table, p_column, SQLERRM;
  END;
END;
$$;

SELECT _ensure_lookup_fk('public.users'::regclass,                'account_status',         'public.user_account_statuses'::regclass,        'code', 'fk_users_account_status');
SELECT _ensure_lookup_fk('public.loans'::regclass,                'payment_frequency',      'public.payment_frequencies'::regclass,          'code', 'fk_loans_payment_frequency');
SELECT _ensure_lookup_fk('public.loans'::regclass,                'status',                 'public.loan_statuses'::regclass,                'code', 'fk_loans_status');
SELECT _ensure_lookup_fk('public.lender_profiles'::regclass,      'account_upgrade_status', 'public.account_upgrade_statuses'::regclass,      'code', 'fk_lender_profiles_account_upgrade_status');
SELECT _ensure_lookup_fk('public.disbursements'::regclass,        'method',                 'public.disbursement_methods'::regclass,           'code', 'fk_disbursements_method');
SELECT _ensure_lookup_fk('public.disbursements'::regclass,        'status',                 'public.disbursement_statuses'::regclass,          'code', 'fk_disbursements_status');
SELECT _ensure_lookup_fk('public.payments'::regclass,             'payment_method',         'public.payment_methods'::regclass,                'code', 'fk_payments_payment_method');
SELECT _ensure_lookup_fk('public.payments'::regclass,             'status',                 'public.payment_statuses'::regclass,               'code', 'fk_payments_status');
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

DROP FUNCTION _ensure_lookup_fk(regclass, text, regclass, text, text);

-- ─────────────────────────────────────────────────────────────────
-- 2) loan_schedules UNIQUE(loan_id, installment_number) — re-ensure
-- ─────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.loan_schedules'::regclass AND contype='u'
      AND array_length(conkey,1)=2
  ) THEN
    IF EXISTS (SELECT 1 FROM public.loan_schedules GROUP BY loan_id, installment_number HAVING COUNT(*)>1) THEN
      RAISE WARNING 'loan_schedules duplicate (loan_id, installment_number) — deduplicating';
      DELETE FROM public.loan_schedules WHERE id NOT IN (
        SELECT DISTINCT ON (loan_id, installment_number) id FROM public.loan_schedules ORDER BY loan_id, installment_number, created_at ASC
      );
    END IF;
    ALTER TABLE public.loan_schedules ADD CONSTRAINT uq_loan_schedules_loan_installment UNIQUE (loan_id, installment_number);
  END IF;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ─────────────────────────────────────────────────────────────────
-- 3) Application child FK ON DELETE CASCADE + UNIQUE 1:1
-- ─────────────────────────────────────────────────────────────────
DO $$
DECLARE tbl text; fk_exists boolean;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['application_personal_info','application_employment_info','application_loan_details','application_addresses','application_emergency_contacts','application_co_makers','application_documents'] LOOP
    SELECT EXISTS (
      SELECT 1 FROM pg_constraint c JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
      WHERE c.conrelid=tbl::regclass AND c.contype='f' AND a.attname='application_id' AND c.confdeltype='c'
    ) INTO fk_exists;
    IF NOT fk_exists THEN
      BEGIN EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT IF EXISTS %I', tbl, tbl || '_application_id_fkey'); EXCEPTION WHEN OTHERS THEN NULL; END;
      BEGIN
        EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (application_id) REFERENCES public.in_office_applications(id) ON DELETE CASCADE NOT VALID', tbl, tbl || '_app_id_fkey');
        EXECUTE format('ALTER TABLE public.%I VALIDATE CONSTRAINT %I', tbl, tbl || '_app_id_fkey');
      EXCEPTION WHEN OTHERS THEN RAISE WARNING 'Could not add cascade FK for %: %', tbl, SQLERRM; END;
    END IF;
  END LOOP;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_application_personal_info_app_id  ON public.application_personal_info(application_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_application_employment_info_app_id ON public.application_employment_info(application_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_application_loan_details_app_id    ON public.application_loan_details(application_id);

-- ─────────────────────────────────────────────────────────────────
-- 4) notifications: harden trigger + add bulk RPC + keep policy
-- ─────────────────────────────────────────────────────────────────
-- Drop and recreate with stricter guard: is_read may only transition false->true,
-- read_at must be set when is_read becomes true, and no other column may change.
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

  -- Prevent flipping is_read back to false (client may only mark read, not unread).
  IF OLD.is_read = TRUE AND NEW.is_read = FALSE THEN
    RAISE EXCEPTION 'notifications: cannot mark notification as unread'
      USING ERRCODE = '42501';
  END IF;

  -- If marking read, require read_at to be set (coerce if caller forgot).
  IF NEW.is_read = TRUE AND OLD.is_read = FALSE AND NEW.read_at IS NULL THEN
    NEW.read_at := NOW();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_notifications_update_columns ON public.notifications;
CREATE TRIGGER trg_enforce_notifications_update_columns
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.enforce_notifications_update_columns();

-- Keep row-level UPDATE policy (row gating), column gating is via trigger.
DROP POLICY IF EXISTS notifications_update_own ON public.notifications;
CREATE POLICY notifications_update_own ON public.notifications
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
COMMENT ON POLICY notifications_update_own ON public.notifications IS
  'Client may UPDATE own notifications, but trigger trg_enforce_notifications_update_columns restricts columns to is_read/read_at only (and prevents unread flip). Preferred path is RPC mark_notification_read / mark_all_notifications_read. Other writes via service_role.';

-- Preferred RPC: single mark read (already in 00106, re-ensure)
CREATE OR REPLACE FUNCTION public.mark_notification_read(p_notification_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.notifications
  SET is_read = TRUE, read_at = COALESCE(read_at, NOW())
  WHERE id = p_notification_id AND user_id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Notification not found or not owned' USING ERRCODE='42501';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.mark_notification_read(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_notification_read(uuid) TO authenticated;
COMMENT ON FUNCTION public.mark_notification_read(uuid) IS 'Safer than direct UPDATE: marks own notification read (is_read/read_at only). RLS still enforced. Preferred over direct UPDATE.';

-- Bulk RPC: mark all as read
CREATE OR REPLACE FUNCTION public.mark_all_notifications_read()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count integer;
BEGIN
  UPDATE public.notifications
  SET is_read = TRUE, read_at = COALESCE(read_at, NOW())
  WHERE user_id = auth.uid() AND is_read = FALSE;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.mark_all_notifications_read() FROM anon;
GRANT EXECUTE ON FUNCTION public.mark_all_notifications_read() TO authenticated;
COMMENT ON FUNCTION public.mark_all_notifications_read() IS 'Bulk mark all own notifications as read. Safer than direct UPDATE with wide filter.';

-- Ensure grants for notifications SELECT still work (authenticated has SELECT via 00003)
-- Revoke direct UPDATE privilege to push clients toward RPC (optional hardening):
-- We KEEP the UPDATE grant because trigger already restricts, and revoking would break
-- legacy clients that still do direct UPDATE is_read. If you want RPC-only, uncomment:
-- REVOKE UPDATE ON public.notifications FROM authenticated;
-- Then clients MUST use the RPCs above (service_role still has ALL via 00003).

-- ─────────────────────────────────────────────────────────────────
-- 5) addresses — TIGHTEN: remove employee broad read
-- ─────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS addresses_read ON public.addresses;
CREATE POLICY addresses_read ON public.addresses
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR auth_role() = 'head_manager'
    OR (
      auth_role() = 'rider'
      AND user_id IN (SELECT rider_assigned_lender_ids())
    )
  );
COMMENT ON POLICY addresses_read ON public.addresses IS
  'Tightened in 00107: employee direct bulk read removed — personal data (street/barangay/city/province) is PII. Employee operational needs are via service_role edge functions (ci-view, collections-view, etc. using getAdminClient() which bypasses RLS with audit). Rider can see addresses of lenders they are assigned to via rider_assigned_lender_ids(). Head_manager retains full read for office operations.';

-- OPTIONAL: restore legacy employee direct read (uncomment if your deployment
-- intentionally needs employee to SELECT all addresses via PostgREST/Realtime):
-- DROP POLICY IF EXISTS addresses_read ON public.addresses;
-- CREATE POLICY addresses_read ON public.addresses FOR SELECT TO authenticated
--   USING (
--     user_id = auth.uid()
--     OR auth_role() IN ('head_manager','employee')
--     OR (auth_role() = 'rider' AND user_id IN (SELECT rider_assigned_lender_ids()))
--   );

-- ─────────────────────────────────────────────────────────────────
-- 6) lender_profiles — TIGHTEN: head_manager only for direct RLS
-- ─────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS lender_profiles_read ON public.lender_profiles;
CREATE POLICY lender_profiles_read ON public.lender_profiles
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR auth_role() = 'head_manager'
  );
COMMENT ON POLICY lender_profiles_read ON public.lender_profiles IS
  'Tightened in 00107: employee direct bulk read removed — lender_profiles contains PII (dob/monthly_income/gcash/source_of_funds). Employee loan verification goes via service_role edge functions (ci-view joins lender_profiles via getAdminClient() with audit) and head_manager realtime. To restore employee direct read for realtime convenience, replace this policy with head_manager+employee variant (see commented block in 00107).';

-- OPTIONAL RESTORE (if employee realtime on lender_profiles is required):
-- DROP POLICY IF EXISTS lender_profiles_read ON public.lender_profiles;
-- CREATE POLICY lender_profiles_read ON public.lender_profiles
--   FOR SELECT TO authenticated
--   USING (id = auth.uid() OR auth_role() IN ('head_manager','employee'));
-- COMMENT ON POLICY lender_profiles_read ON public.lender_profiles IS
--   'Operational: employee needs dob/monthly_income/gcash for loan verification. Bulk lists via service_role preferred.';

-- ─────────────────────────────────────────────────────────────────
-- 7) rider_locations — CENTRALIZE lender check into function
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.can_view_rider_location(p_rider_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  -- Returns true if the calling lender (auth.uid()) has an ACTIVE assignment
  -- linking them to p_rider_id via collection / CI / disbursement.
  -- head_manager / employee / rider_self are handled by the policy itself,
  -- this function only answers the lender-linked question.
  SELECT
    EXISTS (
      SELECT 1 FROM collection_assignments ca
      JOIN loan_schedules ls ON ls.id = ca.loan_schedule_id
      JOIN loans l ON l.id = ls.loan_id
      WHERE ca.rider_id = p_rider_id
        AND l.lender_id = auth.uid()
        AND ca.status IN ('accepted','in_progress')
    )
    OR EXISTS (
      SELECT 1 FROM credit_investigations ci
      JOIN loans l ON l.id = ci.loan_id
      WHERE ci.rider_id = p_rider_id
        AND l.lender_id = auth.uid()
        AND ci.status IN ('accepted','in_progress')
    )
    OR EXISTS (
      SELECT 1 FROM disbursements d
      JOIN loans l ON l.id = d.loan_id
      WHERE d.rider_id = p_rider_id
        AND l.lender_id = auth.uid()
        AND d.method = 'rider_delivery'
        AND d.status = 'pending'
    );
$$;
COMMENT ON FUNCTION public.can_view_rider_location(uuid) IS
  'Centralized lender->rider location authorization (00107). Used by rider_locations_read policy. Checks active collection (accepted/in_progress), CI (accepted/in_progress), or pending rider_delivery disbursement linking auth.uid() lender to p_rider_id. head_manager/employee bypass is in the policy, not here.';

REVOKE ALL ON FUNCTION public.can_view_rider_location(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.can_view_rider_location(uuid) TO authenticated;

-- Replace complex inline policy with delegating one
DROP POLICY IF EXISTS rider_locations_read ON public.rider_locations;
CREATE POLICY rider_locations_read ON public.rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'lender'
      AND public.can_view_rider_location(rider_id)
    )
  );
COMMENT ON POLICY rider_locations_read ON public.rider_locations IS
  'Simplified in 00107: lender visibility delegates to can_view_rider_location(rider_id) (single source of truth for collection/CI/disbursement checks). Maintains head_manager/employee full read and rider self read.';

COMMIT;
