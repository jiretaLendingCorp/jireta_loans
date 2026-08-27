-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00003_rls_grants_storage.sql
-- Purpose   : Consolidated security layer — Row Level Security (enable +
--             policies), privileges/grants, storage buckets + policies,
--             and Supabase Realtime publication. Reproduces the end-state
--             of the original migrations; only final policy versions are
--             emitted (00017/00021/00022 replacements folded in).
--             NOTE: `blacklist` is absent (dropped in 00034), so its
--             policies/grants/realtime entries are intentionally omitted.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) Enable Row Level Security on every application table
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE roles                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE permissions            ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_permissions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE users                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_logs              ENABLE ROW LEVEL SECURITY;
ALTER TABLE terms_consent_logs     ENABLE ROW LEVEL SECURITY;
ALTER TABLE lender_profiles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE rider_profiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE addresses              ENABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_contacts     ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_upgrade_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE loans                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE loan_schedules         ENABLE ROW LEVEL SECURITY;
ALTER TABLE co_makers              ENABLE ROW LEVEL SECURITY;
ALTER TABLE co_maker_documents     ENABLE ROW LEVEL SECURITY;
ALTER TABLE loan_documents         ENABLE ROW LEVEL SECURITY;
ALTER TABLE in_office_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE credit_investigations  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ci_documents           ENABLE ROW LEVEL SECURITY;
ALTER TABLE collection_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE disbursements          ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments               ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_reversals      ENABLE ROW LEVEL SECURITY;
ALTER TABLE rider_locations        ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications          ENABLE ROW LEVEL SECURITY;
ALTER TABLE sms_logs               ENABLE ROW LEVEL SECURITY;
ALTER TABLE sms_templates          ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports                ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_templates       ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs             ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_config          ENABLE ROW LEVEL SECURITY;
ALTER TABLE penalty_logs           ENABLE ROW LEVEL SECURITY;
ALTER TABLE xendit_logs            ENABLE ROW LEVEL SECURITY;
ALTER TABLE otp_codes              ENABLE ROW LEVEL SECURITY;
ALTER TABLE password_history       ENABLE ROW LEVEL SECURITY;

-- Internal infra tables (00023): no direct client access
ALTER TABLE rate_limit_logs        ENABLE ROW LEVEL SECURITY;
ALTER TABLE password_reset_tokens  ENABLE ROW LEVEL SECURITY;

-- 3NF child tables (00022)
ALTER TABLE loan_co_makers ENABLE ROW LEVEL SECURITY;

-- In-office application child tables (00022)
DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'application_personal_info',
    'application_employment_info',
    'application_addresses',
    'application_emergency_contacts',
    'application_loan_details',
    'application_co_makers',
    'application_documents'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY;', tbl);
  END LOOP;
END $$;

-- Reference (lookup) tables (00025)
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'user_account_statuses','account_upgrade_statuses','loan_statuses','payment_statuses',
    'payment_methods','disbursement_methods','disbursement_statuses',
    'collection_assignment_statuses','credit_investigation_statuses',
    'notification_types','relationship_types','payment_frequencies',
    'address_types','document_types','gender_types','civil_statuses',
    'employment_types','vehicle_types','platform_types','sms_statuses',
    'in_office_application_statuses'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY;', t);
  END LOOP;
END $$;

ALTER TABLE loan_disbursement_preferences ENABLE ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────────────────────────────
-- 2) RLS policies (final versions only)
-- ─────────────────────────────────────────────────────────────────────

-- ROLES / PERMISSIONS — all authenticated read roles (navigation);
-- permissions/role_permissions are head_manager + employee only
CREATE POLICY "roles_read_all" ON roles
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "permissions_read_hm" ON permissions
  FOR SELECT TO authenticated
  USING (auth_role() IN ('head_manager','employee'));

CREATE POLICY "role_permissions_read_hm" ON role_permissions
  FOR SELECT TO authenticated
  USING (auth_role() = 'head_manager');

-- USERS — Tightened (00106): employee bulk read removed. Flutter lists go via
-- service_role edge `users-admin?fn=get-list` which enforces RBAC + audit.
-- Direct RLS now allows: own row OR head_manager all. Employee cannot bulk-read
-- sensitive columns (email, phone, fcm_token, last_login_at) via direct query.
CREATE POLICY "users_read_own" ON users
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR auth_role() = 'head_manager'
    OR (
      auth_role() = 'employee'
      AND role_id IN (SELECT id FROM roles WHERE name IN ('lender','rider'))
    )
  );

CREATE POLICY "users_no_direct_insert" ON users
  FOR INSERT TO authenticated WITH CHECK (false);

CREATE POLICY "users_no_direct_update" ON users
  FOR UPDATE TO authenticated USING (false);

-- AUTH LOGS — own records only
CREATE POLICY "auth_logs_own" ON auth_logs
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR auth_role() = 'head_manager');

-- LENDER PROFILES — Tightened (00106): employee direct read remains for operational
-- loan processing, but head_manager is full, employee is documented as needing
-- PII (dob, monthly_income, gcash) for verification. Bulk lender lists for employee
-- are also available via service_role `users-admin` with audit, so direct RLS
-- is kept for realtime but limited to head_manager/employee as before; sensitive
-- outer users rows are already limited by users_read_own.
-- See migration 00106 for alternative stricter option (head_manager only).
CREATE POLICY "lender_profiles_read" ON lender_profiles
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
  );

CREATE POLICY "lender_profiles_no_direct_write" ON lender_profiles
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- RIDER PROFILES — owner reads own; HM/Employee read all
CREATE POLICY "rider_profiles_read" ON rider_profiles
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
  );

-- EMPLOYEE PROFILES — owner or head_manager only
CREATE POLICY "employee_profiles_read" ON employee_profiles
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR auth_role() = 'head_manager'
  );

-- ADDRESSES — owner, HM/Employee all, or rider assigned to the lender.
-- Final version (00017): rider scoping via rider_assigned_lender_ids()
CREATE POLICY "addresses_read" ON addresses
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'rider'
      AND user_id IN (SELECT rider_assigned_lender_ids())
    )
  );

-- EMERGENCY CONTACTS — owner, HM/Employee, or rider assigned to the lender.
-- Final version (00017)
CREATE POLICY "emergency_contacts_read" ON emergency_contacts
  FOR SELECT TO authenticated
  USING (
    lender_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'rider'
      AND lender_id IN (SELECT rider_assigned_lender_ids())
    )
  );

-- ACCOUNT UPGRADE DOCUMENTS — lender reads own; HM/Employee read all
CREATE POLICY "account_upgrade_documents_read" ON account_upgrade_documents
  FOR SELECT TO authenticated
  USING (
    lender_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
  );

-- LOANS — lender reads own; HM/Employee all; rider reads assigned loans.
-- Final version (00017): cycle-breaking helper rider_assigned_loan_ids()
CREATE POLICY "loans_read" ON loans
  FOR SELECT TO authenticated
  USING (
    lender_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'rider'
      AND id IN (SELECT rider_assigned_loan_ids())
    )
  );

-- LOAN SCHEDULES — lender reads own loan schedules; HM/Employee all;
-- rider reads schedules of loans they are assigned to.
-- Final version (00017)
CREATE POLICY "loan_schedules_read" ON loan_schedules
  FOR SELECT TO authenticated
  USING (
    loan_id IN (SELECT auth_own_loan_ids())
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'rider'
      AND loan_id IN (SELECT rider_assigned_loan_ids())
    )
  );

-- CO MAKERS — lender reads co-makers of own loans; HM/Employee all.
-- Final version (00022): co_makers.loan_id was dropped, so access is
-- resolved through loan_co_makers + auth_own_loan_ids()
CREATE POLICY "co_makers_read" ON co_makers
  FOR SELECT TO authenticated
  USING (
    id IN (
      SELECT lcm.co_maker_id FROM loan_co_makers lcm
      WHERE lcm.loan_id IN (SELECT auth_own_loan_ids())
    )
    OR auth_role() IN ('head_manager','employee')
  );

-- LOAN CO MAKERS — lender reads links of own loans; HM/Employee all
CREATE POLICY "loan_co_makers_read" ON loan_co_makers
  FOR SELECT TO authenticated
  USING (
    loan_id IN (SELECT auth_own_loan_ids())
    OR auth_role() IN ('head_manager','employee')
  );

-- CREDIT INVESTIGATIONS — rider reads own; HM/Employee all
CREATE POLICY "ci_read" ON credit_investigations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
  );

-- CI DOCUMENTS — rider reads docs of their own CI; HM/Employee all.
-- Final version (00017)
CREATE POLICY "ci_documents_read" ON ci_documents
  FOR SELECT TO authenticated
  USING (
    ci_id IN (
      SELECT id FROM credit_investigations WHERE rider_id = auth.uid()
    )
    OR auth_role() IN ('head_manager','employee')
  );

-- COLLECTION ASSIGNMENTS — rider reads own; HM/Employee all; lender reads
-- assignments on their loans. Final version (00021): loan resolved through
-- loan_schedules since collection_assignments.loan_id was dropped
CREATE POLICY "collection_assignments_read" ON collection_assignments
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR EXISTS (
      SELECT 1
      FROM loan_schedules ls
      JOIN loans l ON l.id = ls.loan_id
      WHERE ls.id = collection_assignments.loan_schedule_id
        AND l.lender_id = auth.uid()
    )
  );

-- DISBURSEMENTS — rider reads own; HM/Employee all; lender reads own loans'
-- disbursements
CREATE POLICY "disbursements_read" ON disbursements
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR loan_id IN (SELECT id FROM loans WHERE lender_id = auth.uid())
  );

-- PAYMENTS — HM/Employee all; lender reads payments on own loans.
-- Final version (00021): loan resolved through loan_schedules /
-- collection_assignments since payments.loan_id was dropped
CREATE POLICY "payments_read" ON payments
  FOR SELECT TO authenticated
  USING (
    auth_role() IN ('head_manager','employee')
    OR EXISTS (
      SELECT 1
      FROM loan_schedules ls
      JOIN loans l ON l.id = ls.loan_id
      WHERE ls.id = payments.loan_schedule_id
        AND l.lender_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM collection_assignments ca
      JOIN loan_schedules ls ON ls.id = ca.loan_schedule_id
      JOIN loans l ON l.id = ls.loan_id
      WHERE ca.id = payments.collection_assignment_id
        AND l.lender_id = auth.uid()
    )
  );

-- NOTIFICATIONS — own only for SELECT; UPDATE limited to is_read/read_at via trigger
-- (see enforce_notifications_update_columns in 00002). Client may mark own
-- notifications read; other columns are blocked by BEFORE UPDATE trigger.
CREATE POLICY "notifications_own" ON notifications
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "notifications_update_own" ON notifications
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- RIDER LOCATIONS — rider reads own; HM/Employee all; lender reads active
-- riders assigned to them. Final version (00021)
CREATE POLICY "rider_locations_read" ON rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'lender'
      AND EXISTS (
        SELECT 1
        FROM collection_assignments ca
        JOIN loan_schedules ls ON ls.id = ca.loan_schedule_id
        JOIN loans l ON l.id = ls.loan_id
        WHERE ca.rider_id = rider_locations.rider_id
          AND l.lender_id = auth.uid()
          AND ca.status IN ('accepted','in_progress')
      )
    )
  );

-- AUDIT LOGS — HM only (read-only)
CREATE POLICY "audit_logs_hm_only" ON audit_logs
  FOR SELECT TO authenticated
  USING (auth_role() = 'head_manager');

-- REPORTS — HM only
CREATE POLICY "reports_hm_only" ON reports
  FOR SELECT TO authenticated
  USING (auth_role() = 'head_manager');

CREATE POLICY "report_templates_read" ON report_templates
  FOR SELECT TO authenticated
  USING (auth_role() = 'head_manager');

-- SYSTEM CONFIG — HM only
CREATE POLICY "system_config_hm" ON system_config
  FOR SELECT TO authenticated
  USING (auth_role() = 'head_manager');

-- PENALTY LOGS — HM/Employee read all; lender reads own loans' penalties
CREATE POLICY "penalty_logs_read" ON penalty_logs
  FOR SELECT TO authenticated
  USING (
    auth_role() IN ('head_manager','employee')
    OR loan_id IN (SELECT id FROM loans WHERE lender_id = auth.uid())
  );

-- IN OFFICE APPLICATIONS — creator or head_manager
CREATE POLICY "in_office_read" ON in_office_applications
  FOR SELECT TO authenticated
  USING (
    created_by = auth.uid()
    OR auth_role() = 'head_manager'
  );

-- In-office application child tables — creator or head_manager.
-- Uses application_owner() to look up the parent's creator (00022)
DO $$
DECLARE
  tbl TEXT;
  policy_name TEXT;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'application_personal_info',
    'application_employment_info',
    'application_addresses',
    'application_emergency_contacts',
    'application_loan_details',
    'application_co_makers',
    'application_documents'
  ] LOOP
    policy_name := tbl || '_read';
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR SELECT TO authenticated
       USING (application_owner(application_id) = auth.uid()
              OR auth_role() = ''head_manager'');',
      policy_name, tbl);
  END LOOP;
END $$;

-- SMS LOGS — HM reads all
CREATE POLICY "sms_logs_read" ON sms_logs
  FOR SELECT TO authenticated
  USING (auth_role() = 'head_manager');

-- SMS TEMPLATES — HM reads/writes
CREATE POLICY "sms_templates_read" ON sms_templates
  FOR SELECT TO authenticated
  USING (auth_role() = 'head_manager');

-- LOAN DISBURSEMENT PREFERENCES — lender reads own loans' preference;
-- HM/Employee all
CREATE POLICY "loan_disbursement_preferences_read" ON loan_disbursement_preferences
  FOR SELECT TO authenticated
  USING (
    loan_id IN (SELECT auth_own_loan_ids())
    OR auth_role() IN ('head_manager','employee')
  );

-- Reference (lookup) tables — read-only for anon + authenticated (00025);
-- service_role (edge functions) bypasses RLS to maintain the main tables
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'user_account_statuses','account_upgrade_statuses','loan_statuses','payment_statuses',
    'payment_methods','disbursement_methods','disbursement_statuses',
    'collection_assignment_statuses','credit_investigation_statuses',
    'notification_types','relationship_types','payment_frequencies',
    'address_types','document_types','gender_types','civil_statuses',
    'employment_types','vehicle_types','platform_types','sms_statuses',
    'in_office_application_statuses'
  ] LOOP
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT TO anon, authenticated USING (true);',
                   t || '_read', t);
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 3) Views run with the caller's privileges so RLS applies (00023)
-- ─────────────────────────────────────────────────────────────────────

ALTER VIEW v_loan_schedules  SET (security_invoker = true);
ALTER VIEW v_loan_financials SET (security_invoker = true);

-- ─────────────────────────────────────────────────────────────────────
-- 4) Privileges / grants (00007)
--    Newer Supabase projects no longer auto-grant USAGE on public, and
--    auto_expose_new_tables is unset — every table/sequence must be
--    explicitly granted or PostgREST returns "permission denied for
--    schema public" (42501).
-- ─────────────────────────────────────────────────────────────────────

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- service_role (edge functions): full access, bypasses RLS
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL ROUTINES  IN SCHEMA public TO service_role;

-- anon and authenticated: SELECT only (RLS policies restrict further)
GRANT SELECT ON ALL TABLES    IN SCHEMA public TO anon, authenticated;
GRANT USAGE  ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;

-- loan_disbursement_preferences: service_role read/write (00031)
GRANT SELECT, INSERT, UPDATE, DELETE ON loan_disbursement_preferences TO service_role;

-- Internal infra tables: no direct client access (00023). service_role
-- keeps its privileges via the superuser bypass.
REVOKE ALL ON TABLE rate_limit_logs        FROM anon, authenticated;
REVOKE ALL ON TABLE password_reset_tokens  FROM anon, authenticated;

-- Default privileges — cover objects created after this migration
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

-- ─────────────────────────────────────────────────────────────────────
-- 5) Storage buckets + policies (00013, 00015, 00030)
--    avatars: public read + authenticated upload
--    account-upgrade-documents / ci-documents: private, owner-scoped
-- ─────────────────────────────────────────────────────────────────────

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('avatars', 'avatars', TRUE, 5242880, ARRAY['image/png','image/jpeg','image/webp']::text[])
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('account-upgrade-documents', 'account-upgrade-documents', FALSE, 10485760,
        ARRAY['image/png','image/jpeg','image/webp','application/pdf']::text[])
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('ci-documents', 'ci-documents', FALSE, 10485760,
        ARRAY['image/png','image/jpeg','image/webp','application/pdf']::text[])
ON CONFLICT (id) DO NOTHING;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'avatars_public_read'
  ) THEN
    CREATE POLICY "avatars_public_read" ON storage.objects
      FOR SELECT USING (bucket_id = 'avatars');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'avatars_auth_upload'
  ) THEN
    CREATE POLICY "avatars_auth_upload" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'avatars');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'account_upgrade_docs_own_read'
  ) THEN
    CREATE POLICY "account_upgrade_docs_own_read" ON storage.objects
      FOR SELECT TO authenticated
      USING (bucket_id = 'account-upgrade-documents' AND owner = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'account_upgrade_docs_own_upload'
  ) THEN
    CREATE POLICY "account_upgrade_docs_own_upload" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'account-upgrade-documents' AND owner = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'account_upgrade_docs_own_update'
  ) THEN
    CREATE POLICY "account_upgrade_docs_own_update" ON storage.objects
      FOR UPDATE TO authenticated
      USING (bucket_id = 'account-upgrade-documents' AND owner = auth.uid())
      WITH CHECK (bucket_id = 'account-upgrade-documents' AND owner = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'account_upgrade_docs_own_delete'
  ) THEN
    CREATE POLICY "account_upgrade_docs_own_delete" ON storage.objects
      FOR DELETE TO authenticated
      USING (bucket_id = 'account-upgrade-documents' AND owner = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'ci_docs_own_read'
  ) THEN
    CREATE POLICY "ci_docs_own_read" ON storage.objects
      FOR SELECT TO authenticated
      USING (bucket_id = 'ci-documents' AND owner = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'ci_docs_own_upload'
  ) THEN
    CREATE POLICY "ci_docs_own_upload" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'ci-documents' AND owner = auth.uid());
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────
-- 6) Supabase Realtime (00026) — publish CDC for the domain tables the
--    Flutter app subscribes to. Events are filtered by RLS using the
--    connected user's JWT. NOTE: `blacklist` was dropped in 00034, so it
--    is excluded here.
-- ─────────────────────────────────────────────────────────────────────

ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.loans;
ALTER PUBLICATION supabase_realtime ADD TABLE public.loan_schedules;
ALTER PUBLICATION supabase_realtime ADD TABLE public.payments;
ALTER PUBLICATION supabase_realtime ADD TABLE public.collection_assignments;
ALTER PUBLICATION supabase_realtime ADD TABLE public.credit_investigations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.ci_documents;
ALTER PUBLICATION supabase_realtime ADD TABLE public.account_upgrade_documents;
ALTER PUBLICATION supabase_realtime ADD TABLE public.lender_profiles;
ALTER PUBLICATION supabase_realtime ADD TABLE public.rider_profiles;
ALTER PUBLICATION supabase_realtime ADD TABLE public.employee_profiles;
ALTER PUBLICATION supabase_realtime ADD TABLE public.users;
ALTER PUBLICATION supabase_realtime ADD TABLE public.in_office_applications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.disbursements;
ALTER PUBLICATION supabase_realtime ADD TABLE public.reports;
ALTER PUBLICATION supabase_realtime ADD TABLE public.audit_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE public.penalty_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE public.system_config;

COMMIT;
