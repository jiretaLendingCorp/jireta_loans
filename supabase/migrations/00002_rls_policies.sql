-- /supabase/migrations/00002_rls_policies.sql
-- Row Level Security Policies — All tables locked down
-- Edge Functions use service_role key and bypass RLS
-- Flutter (anon/user keys) is restricted by these policies

BEGIN;

-- Enable RLS on all tables
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
ALTER TABLE kyc_documents          ENABLE ROW LEVEL SECURITY;
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
ALTER TABLE blacklist              ENABLE ROW LEVEL SECURITY;
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper function: get role of authenticated user
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION auth_role()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT r.name
  FROM users u
  JOIN roles r ON r.id = u.role_id
  WHERE u.id = auth.uid()
    AND u.account_status = 'active'
  LIMIT 1;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- PUBLIC: All authenticated users can read roles (for navigation)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "roles_read_all" ON roles
  FOR SELECT TO authenticated USING (true);

CREATE POLICY "permissions_read_hm" ON permissions
  FOR SELECT TO authenticated
  USING (auth_role() IN ('head_manager','employee'));

CREATE POLICY "role_permissions_read_hm" ON role_permissions
  FOR SELECT TO authenticated
  USING (auth_role() = 'head_manager');

-- ─────────────────────────────────────────────────────────────────────────────
-- USERS — Flutter only reads own profile; all mutations via Edge Functions
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "users_read_own" ON users
  FOR SELECT TO authenticated
  USING (id = auth.uid() OR auth_role() IN ('head_manager','employee'));

CREATE POLICY "users_no_direct_insert" ON users
  FOR INSERT TO authenticated WITH CHECK (false);

CREATE POLICY "users_no_direct_update" ON users
  FOR UPDATE TO authenticated USING (false);

-- ─────────────────────────────────────────────────────────────────────────────
-- AUTH LOGS — own records only
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "auth_logs_own" ON auth_logs
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR auth_role() = 'head_manager');

-- ─────────────────────────────────────────────────────────────────────────────
-- LENDER PROFILES
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "lender_profiles_read" ON lender_profiles
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
  );

CREATE POLICY "lender_profiles_no_direct_write" ON lender_profiles
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

-- ─────────────────────────────────────────────────────────────────────────────
-- RIDER PROFILES
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "rider_profiles_read" ON rider_profiles
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- EMPLOYEE PROFILES
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "employee_profiles_read" ON employee_profiles
  FOR SELECT TO authenticated
  USING (
    id = auth.uid()
    OR auth_role() = 'head_manager'
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- ADDRESSES — lender can read own; HM/Employee can read all
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "addresses_read" ON addresses
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR auth_role() = 'rider'
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- EMERGENCY CONTACTS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "emergency_contacts_read" ON emergency_contacts
  FOR SELECT TO authenticated
  USING (
    lender_id = auth.uid()
    OR auth_role() IN ('head_manager','employee','rider')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- KYC DOCUMENTS — lender reads own; HM/Employee read all
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "kyc_documents_read" ON kyc_documents
  FOR SELECT TO authenticated
  USING (
    lender_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- LOANS — lender reads own; HM/Employee read all; Rider reads assigned loans
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "loans_read" ON loans
  FOR SELECT TO authenticated
  USING (
    lender_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'rider'
      AND id IN (
        SELECT loan_id FROM credit_investigations WHERE rider_id = auth.uid()
        UNION
        SELECT loan_id FROM collection_assignments WHERE rider_id = auth.uid()
      )
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- LOAN SCHEDULES
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "loan_schedules_read" ON loan_schedules
  FOR SELECT TO authenticated
  USING (
    loan_id IN (SELECT id FROM loans)
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- CO MAKERS — lender + HM/Employee can read
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "co_makers_read" ON co_makers
  FOR SELECT TO authenticated
  USING (
    loan_id IN (SELECT id FROM loans)
    AND auth_role() IN ('head_manager','employee','lender')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- CREDIT INVESTIGATIONS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "ci_read" ON credit_investigations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- CI DOCUMENTS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "ci_documents_read" ON ci_documents
  FOR SELECT TO authenticated
  USING (
    ci_id IN (SELECT id FROM credit_investigations)
    AND auth_role() IN ('head_manager','employee','rider')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- COLLECTION ASSIGNMENTS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "collection_assignments_read" ON collection_assignments
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR loan_id IN (SELECT id FROM loans WHERE lender_id = auth.uid())
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- DISBURSEMENTS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "disbursements_read" ON disbursements
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR loan_id IN (SELECT id FROM loans WHERE lender_id = auth.uid())
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- PAYMENTS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "payments_read" ON payments
  FOR SELECT TO authenticated
  USING (
    loan_id IN (SELECT id FROM loans WHERE lender_id = auth.uid())
    OR auth_role() IN ('head_manager','employee')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- NOTIFICATIONS — own only
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "notifications_own" ON notifications
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- RIDER LOCATIONS — rider reads own; HM/Employee reads all; Lender reads active rider
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "rider_locations_read" ON rider_locations
  FOR SELECT TO authenticated
  USING (
    rider_id = auth.uid()
    OR auth_role() IN ('head_manager','employee')
    OR (
      auth_role() = 'lender'
      AND rider_id IN (
        SELECT ca.rider_id FROM collection_assignments ca
        JOIN loans l ON l.id = ca.loan_id
        WHERE l.lender_id = auth.uid()
          AND ca.status IN ('accepted','in_progress')
      )
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- AUDIT LOGS — HM only (read-only)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "audit_logs_hm_only" ON audit_logs
  FOR SELECT TO authenticated
  USING (auth_role() = 'head_manager');

-- ─────────────────────────────────────────────────────────────────────────────
-- REPORTS — HM only
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "reports_hm_only" ON reports
  FOR SELECT TO authenticated
  USING (auth_role() = 'head_manager');

CREATE POLICY "report_templates_read" ON report_templates
  FOR SELECT TO authenticated
  USING (auth_role() = 'head_manager');

-- ─────────────────────────────────────────────────────────────────────────────
-- SYSTEM CONFIG — HM only
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "system_config_hm" ON system_config
  FOR SELECT TO authenticated
  USING (auth_role() = 'head_manager');

-- ─────────────────────────────────────────────────────────────────────────────
-- BLACKLIST — HM reads all; Employee reads list (no add/remove)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "blacklist_hm_read" ON blacklist
  FOR SELECT TO authenticated
  USING (auth_role() IN ('head_manager','employee'));

-- ─────────────────────────────────────────────────────────────────────────────
-- PENALTY LOGS — HM/Employee read
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "penalty_logs_read" ON penalty_logs
  FOR SELECT TO authenticated
  USING (
    auth_role() IN ('head_manager','employee')
    OR loan_id IN (SELECT id FROM loans WHERE lender_id = auth.uid())
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- IN OFFICE APPLICATIONS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "in_office_read" ON in_office_applications
  FOR SELECT TO authenticated
  USING (
    created_by = auth.uid()
    OR auth_role() = 'head_manager'
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- SMS LOGS — HM reads all
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "sms_logs_read" ON sms_logs
  FOR SELECT TO authenticated
  USING (auth_role() = 'head_manager');

-- ─────────────────────────────────────────────────────────────────────────────
-- SMS TEMPLATES — HM reads/writes
-- ─────────────────────────────────────────────────────────────────────────────
CREATE POLICY "sms_templates_read" ON sms_templates
  FOR SELECT TO authenticated
  USING (auth_role() = 'head_manager');

COMMIT;