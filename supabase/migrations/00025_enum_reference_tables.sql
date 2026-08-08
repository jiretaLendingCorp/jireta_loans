-- /supabase/migrations/00025_enum_reference_tables.sql
-- 3NF normalization pass — part 3: replace in-line enum CHECK constraints
-- with reference (lookup) tables and enforce them via foreign keys on the
-- string `code`. This keeps the application layer (edge functions + Flutter)
-- writing/reading plain strings while giving the database a single controlled
-- vocabulary per domain value, with human-readable labels and descriptions.
--
-- Also adds the missing integrity constraints found in the schema audit:
--   • loans.interest_rate / application_loan_details.interest_rate ∈ [0,100]
--   • penalty_logs.penalty_rate >= 0
--   • latitude ∈ [-90,90] / longitude ∈ [-180,180] on addresses,
--     rider_locations and application_addresses
--   • partial UNIQUE on collection_assignments(loan_schedule_id, rider_id)
--     for ACTIVE assignments (prevents duplicate active assignments while
--     still allowing a rider to be reassigned after a failed/completed run)
--
-- REFERENCES ON `code`: each lookup table defines `code VARCHAR(100) UNIQUE`.
-- The FK from an existing varchar column points at that code, so Postgres
-- enforces the vocabulary without requiring uuid joins in the app layer.
--
-- NOTE ON ORDERING: FKs are added BEFORE the redundant CHECK constraints are
-- dropped, so the column stays constrained the entire time.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Reference tables
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE user_account_statuses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE kyc_statuses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE loan_statuses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE payment_statuses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE payment_methods (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE disbursement_methods (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE disbursement_statuses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE collection_assignment_statuses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE credit_investigation_statuses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE notification_types (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE relationship_types (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE payment_frequencies (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE address_types (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE document_types (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE gender_types (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE civil_statuses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE employment_types (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE vehicle_types (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE platform_types (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE sms_statuses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE in_office_application_statuses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        VARCHAR(100) NOT NULL UNIQUE,
  label       VARCHAR(100) NOT NULL,
  description TEXT,
  is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
  sort_order  INTEGER      NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Seed the controlled vocabularies (ON CONFLICT keeps this idempotent).
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO user_account_statuses (code, label, sort_order) VALUES
  ('active',    'Active',    1),
  ('inactive',  'Inactive',  2),
  ('suspended', 'Suspended', 3),
  ('archived',  'Archived',  4);

INSERT INTO kyc_statuses (code, label, sort_order) VALUES
  ('pending',   'Pending',   1),
  ('submitted', 'Submitted', 2),
  ('verified',  'Verified',  3),
  ('rejected',  'Rejected',  4);

INSERT INTO loan_statuses (code, label, sort_order) VALUES
  ('pending',       'Pending',          1),
  ('kyc_required',  'KYC Required',     2),
  ('under_review',  'Under Review',     3),
  ('ci_assigned',   'CI Assigned',      4),
  ('ci_completed',  'CI Completed',     5),
  ('approved',      'Approved',         6),
  ('rejected',      'Rejected',         7),
  ('active',        'Active',           8),
  ('completed',     'Completed',        9),
  ('cancelled',     'Cancelled',       10),
  ('overdue',       'Overdue',         11);

INSERT INTO payment_statuses (code, label, sort_order) VALUES
  ('pending',  'Pending',  1),
  ('verified', 'Verified', 2),
  ('reversed', 'Reversed', 3);

INSERT INTO payment_methods (code, label, sort_order) VALUES
  ('gcash_xendit',   'GCash (Xendit)',  1),
  ('office_cash',    'Office Cash',     2),
  ('rider_collection','Rider Collection',3);

INSERT INTO disbursement_methods (code, label, sort_order) VALUES
  ('gcash',          'GCash',          1),
  ('office_cash',    'Office Cash',    2),
  ('rider_delivery', 'Rider Delivery', 3);

INSERT INTO disbursement_statuses (code, label, sort_order) VALUES
  ('pending',    'Pending',    1),
  ('processing', 'Processing', 2),
  ('completed',  'Completed',  3),
  ('failed',     'Failed',     4);

INSERT INTO collection_assignment_statuses (code, label, sort_order) VALUES
  ('assigned',   'Assigned',    1),
  ('accepted',   'Accepted',    2),
  ('declined',   'Declined',    3),
  ('in_progress','In Progress', 4),
  ('completed',  'Completed',   5),
  ('failed',     'Failed',      6);

INSERT INTO credit_investigation_statuses (code, label, sort_order) VALUES
  ('assigned',   'Assigned',    1),
  ('accepted',   'Accepted',    2),
  ('declined',   'Declined',    3),
  ('in_progress','In Progress', 4),
  ('completed',  'Completed',   5);

INSERT INTO notification_types (code, label, sort_order) VALUES
  ('loan_applied',           'Loan Applied',            1),
  ('loan_approved',          'Loan Approved',           2),
  ('loan_rejected',          'Loan Rejected',           3),
  ('kyc_required',           'KYC Required',            4),
  ('kyc_submitted',          'KYC Submitted',           5),
  ('kyc_update',             'KYC Update',              6),
  ('ci_required',            'CI Required',             7),
  ('ci_assigned',            'CI Assigned',             8),
  ('ci_completed',           'CI Completed',            9),
  ('ci_accepted',            'CI Accepted',            10),
  ('ci_declined',            'CI Declined',            11),
  ('payment_recorded',       'Payment Recorded',       12),
  ('payment_verified',       'Payment Verified',       13),
  ('payment_reversed',       'Payment Reversed',       14),
  ('payment_collected',      'Payment Collected',      15),
  ('penalty_applied',        'Penalty Applied',        16),
  ('collection_assigned',    'Collection Assigned',    17),
  ('collection_accepted',    'Collection Accepted',    18),
  ('collection_declined',    'Collection Declined',    19),
  ('disbursement',           'Disbursement',           20),
  ('account_status_change',  'Account Status Change',  21),
  ('user_created',           'User Created',           22),
  ('system',                 'System',                 23),
  ('general',                'General',                24),
  ('loan',                   'Loan',                   25),
  ('payment',                'Payment',                26),
  ('collection',             'Collection',             27);

INSERT INTO relationship_types (code, label, sort_order) VALUES
  ('Spouse',    'Spouse',    1),
  ('Parent',    'Parent',    2),
  ('Sibling',   'Sibling',   3),
  ('Child',     'Child',     4),
  ('Relative',  'Relative',  5),
  ('Friend',    'Friend',    6),
  ('Colleague', 'Colleague', 7),
  ('Employer',  'Employer',  8),
  ('Other',     'Other',     9);

INSERT INTO payment_frequencies (code, label, sort_order) VALUES
  ('daily',   'Daily',   1),
  ('weekly',  'Weekly',  2),
  ('monthly', 'Monthly', 3);

INSERT INTO address_types (code, label, sort_order) VALUES
  ('home',       'Home',       1),
  ('work',       'Work',       2),
  ('provincial', 'Provincial', 3);

INSERT INTO document_types (code, label, sort_order) VALUES
  ('valid_id',                   'Valid ID',                   1),
  ('proof_of_income',            'Proof of Income',            2),
  ('barangay_clearance',         'Barangay Clearance',         3),
  ('pay_slip',                   'Pay Slip',                   4),
  ('selfie',                     'Selfie',                     5),
  ('proof_of_billing',           'Proof of Billing',           6),
  ('certificate_of_employment',  'Certificate of Employment',  7),
  ('itr',                        'ITR',                        8),
  ('business_registration',      'Business Registration',      9),
  ('co_maker',                   'Co-Maker',                  10),
  ('ci_photo',                   'CI Photo',                  11),
  ('evidence',                   'Evidence',                  12),
  ('site_photo',                 'Site Photo',                13),
  ('neighbor_interview',         'Neighbor Interview',        14),
  ('proof_of_residence',         'Proof of Residence',        15),
  ('other',                      'Other',                     16);

INSERT INTO gender_types (code, label, sort_order) VALUES
  ('male',   'Male',   1),
  ('female', 'Female', 2),
  ('other',  'Other',  3);

INSERT INTO civil_statuses (code, label, sort_order) VALUES
  ('single',    'Single',    1),
  ('married',   'Married',   2),
  ('widowed',   'Widowed',   3),
  ('separated', 'Separated', 4);

INSERT INTO employment_types (code, label, sort_order) VALUES
  ('employed',       'Employed',       1),
  ('self_employed',  'Self-Employed',  2),
  ('unemployed',     'Unemployed',     3),
  ('student',        'Student',        4),
  ('business_owner', 'Business Owner', 5),
  ('ofw',            'OFW',            6),
  ('freelancer',     'Freelancer',     7);

INSERT INTO vehicle_types (code, label, sort_order) VALUES
  ('Motorcycle', 'Motorcycle', 1),
  ('Bicycle',    'Bicycle',    2),
  ('Car',        'Car',        3);

INSERT INTO platform_types (code, label, sort_order) VALUES
  ('ios',     'iOS',     1),
  ('android', 'Android', 2),
  ('web',     'Web',     3);

INSERT INTO sms_statuses (code, label, sort_order) VALUES
  ('sent',    'Sent',    1),
  ('failed',  'Failed',  2),
  ('pending', 'Pending', 3);

INSERT INTO in_office_application_statuses (code, label, sort_order) VALUES
  ('draft',     'Draft',     1),
  ('submitted', 'Submitted', 2),
  ('converted', 'Converted', 3);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Foreign keys: main-table varchar columns → lookup `code`.
--    NULL is permitted wherever the underlying column is nullable.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE users
  ADD CONSTRAINT fk_users_account_status
    FOREIGN KEY (account_status) REFERENCES user_account_statuses(code);

ALTER TABLE lender_profiles
  ADD CONSTRAINT fk_lender_profiles_kyc_status
    FOREIGN KEY (kyc_status) REFERENCES kyc_statuses(code),
  ADD CONSTRAINT fk_lender_profiles_gender
    FOREIGN KEY (gender) REFERENCES gender_types(code),
  ADD CONSTRAINT fk_lender_profiles_civil_status
    FOREIGN KEY (civil_status) REFERENCES civil_statuses(code),
  ADD CONSTRAINT fk_lender_profiles_employment_type
    FOREIGN KEY (employment_type) REFERENCES employment_types(code);

ALTER TABLE employee_profiles
  ADD CONSTRAINT fk_employee_profiles_gender
    FOREIGN KEY (gender) REFERENCES gender_types(code),
  ADD CONSTRAINT fk_employee_profiles_civil_status
    FOREIGN KEY (civil_status) REFERENCES civil_statuses(code);

ALTER TABLE kyc_documents
  ADD CONSTRAINT fk_kyc_documents_status
    FOREIGN KEY (status) REFERENCES kyc_statuses(code),
  ADD CONSTRAINT fk_kyc_documents_document_type
    FOREIGN KEY (document_type) REFERENCES document_types(code);

ALTER TABLE loans
  ADD CONSTRAINT fk_loans_status
    FOREIGN KEY (status) REFERENCES loan_statuses(code),
  ADD CONSTRAINT fk_loans_payment_frequency
    FOREIGN KEY (payment_frequency) REFERENCES payment_frequencies(code);

ALTER TABLE payments
  ADD CONSTRAINT fk_payments_status
    FOREIGN KEY (status) REFERENCES payment_statuses(code),
  ADD CONSTRAINT fk_payments_payment_method
    FOREIGN KEY (payment_method) REFERENCES payment_methods(code);

ALTER TABLE disbursements
  ADD CONSTRAINT fk_disbursements_method
    FOREIGN KEY (method) REFERENCES disbursement_methods(code),
  ADD CONSTRAINT fk_disbursements_status
    FOREIGN KEY (status) REFERENCES disbursement_statuses(code);

ALTER TABLE collection_assignments
  ADD CONSTRAINT fk_collection_assignments_status
    FOREIGN KEY (status) REFERENCES collection_assignment_statuses(code);

ALTER TABLE credit_investigations
  ADD CONSTRAINT fk_credit_investigations_status
    FOREIGN KEY (status) REFERENCES credit_investigation_statuses(code);

ALTER TABLE notifications
  ADD CONSTRAINT fk_notifications_type
    FOREIGN KEY (type) REFERENCES notification_types(code);

ALTER TABLE loan_co_makers
  ADD CONSTRAINT fk_loan_co_makers_relationship
    FOREIGN KEY (relationship) REFERENCES relationship_types(code);

ALTER TABLE emergency_contacts
  ADD CONSTRAINT fk_emergency_contacts_relationship
    FOREIGN KEY (relationship) REFERENCES relationship_types(code);

ALTER TABLE addresses
  ADD CONSTRAINT fk_addresses_address_type
    FOREIGN KEY (address_type) REFERENCES address_types(code);

ALTER TABLE rider_profiles
  ADD CONSTRAINT fk_rider_profiles_vehicle_type
    FOREIGN KEY (vehicle_type) REFERENCES vehicle_types(code);

ALTER TABLE terms_consent_logs
  ADD CONSTRAINT fk_terms_consent_logs_platform
    FOREIGN KEY (platform) REFERENCES platform_types(code);

ALTER TABLE sms_logs
  ADD CONSTRAINT fk_sms_logs_status
    FOREIGN KEY (status) REFERENCES sms_statuses(code);

ALTER TABLE in_office_applications
  ADD CONSTRAINT fk_in_office_applications_status
    FOREIGN KEY (status) REFERENCES in_office_application_statuses(code);

-- 00022 child tables
ALTER TABLE application_loan_details
  ADD CONSTRAINT fk_application_loan_details_payment_frequency
    FOREIGN KEY (payment_frequency) REFERENCES payment_frequencies(code);

ALTER TABLE application_personal_info
  ADD CONSTRAINT fk_application_personal_info_gender
    FOREIGN KEY (gender) REFERENCES gender_types(code),
  ADD CONSTRAINT fk_application_personal_info_civil_status
    FOREIGN KEY (civil_status) REFERENCES civil_statuses(code);

ALTER TABLE application_employment_info
  ADD CONSTRAINT fk_application_employment_info_employment_type
    FOREIGN KEY (employment_type) REFERENCES employment_types(code);

ALTER TABLE application_addresses
  ADD CONSTRAINT fk_application_addresses_address_type
    FOREIGN KEY (address_type) REFERENCES address_types(code);

ALTER TABLE application_emergency_contacts
  ADD CONSTRAINT fk_application_emergency_contacts_relationship
    FOREIGN KEY (relationship) REFERENCES relationship_types(code);

ALTER TABLE application_co_makers
  ADD CONSTRAINT fk_application_co_makers_relationship
    FOREIGN KEY (relationship) REFERENCES relationship_types(code);

ALTER TABLE application_documents
  ADD CONSTRAINT fk_application_documents_document_type
    FOREIGN KEY (document_type) REFERENCES document_types(code);

ALTER TABLE loan_documents
  ADD CONSTRAINT fk_loan_documents_document_type
    FOREIGN KEY (document_type) REFERENCES document_types(code);

ALTER TABLE ci_documents
  ADD CONSTRAINT fk_ci_documents_document_type
    FOREIGN KEY (document_type) REFERENCES document_types(code);

ALTER TABLE co_maker_documents
  ADD CONSTRAINT fk_co_maker_documents_document_type
    FOREIGN KEY (document_type) REFERENCES document_types(code);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) Drop the in-line enum CHECKs now that the FKs enforce the vocabulary.
--    (Numeric/other checks are intentionally left in place.)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE users                        DROP CONSTRAINT users_account_status_check;
ALTER TABLE lender_profiles               DROP CONSTRAINT lender_profiles_kyc_status_check;
ALTER TABLE lender_profiles               DROP CONSTRAINT lender_profiles_gender_check;
ALTER TABLE lender_profiles               DROP CONSTRAINT lender_profiles_civil_status_check;
ALTER TABLE lender_profiles               DROP CONSTRAINT lender_profiles_employment_type_check;
ALTER TABLE employee_profiles             DROP CONSTRAINT employee_profiles_gender_check;
ALTER TABLE employee_profiles             DROP CONSTRAINT employee_profiles_civil_status_check;
ALTER TABLE kyc_documents                 DROP CONSTRAINT kyc_documents_status_check;
ALTER TABLE kyc_documents                 DROP CONSTRAINT kyc_documents_document_type_check;
ALTER TABLE loans                         DROP CONSTRAINT loans_status_check;
ALTER TABLE loans                         DROP CONSTRAINT loans_payment_frequency_check;
ALTER TABLE payments                      DROP CONSTRAINT payments_status_check;
ALTER TABLE payments                      DROP CONSTRAINT payments_payment_method_check;
ALTER TABLE disbursements                 DROP CONSTRAINT disbursements_method_check;
ALTER TABLE disbursements                 DROP CONSTRAINT disbursements_status_check;
ALTER TABLE collection_assignments        DROP CONSTRAINT collection_assignments_status_check;
ALTER TABLE credit_investigations         DROP CONSTRAINT credit_investigations_status_check;
ALTER TABLE addresses                     DROP CONSTRAINT addresses_address_type_check;
ALTER TABLE rider_profiles                DROP CONSTRAINT rider_profiles_vehicle_type_check;
ALTER TABLE terms_consent_logs            DROP CONSTRAINT terms_consent_logs_platform_check;
ALTER TABLE sms_logs                      DROP CONSTRAINT sms_logs_status_check;
ALTER TABLE in_office_applications        DROP CONSTRAINT in_office_applications_status_check;
ALTER TABLE application_loan_details      DROP CONSTRAINT application_loan_details_payment_frequency_check;
ALTER TABLE application_addresses         DROP CONSTRAINT application_addresses_address_type_check;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) Missing integrity constraints (numeric ranges / geo bounds)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE loans
  ADD CONSTRAINT loans_interest_rate_check
    CHECK (interest_rate >= 0 AND interest_rate <= 100);

ALTER TABLE application_loan_details
  ADD CONSTRAINT application_loan_details_interest_rate_check
    CHECK (interest_rate >= 0 AND interest_rate <= 100);

ALTER TABLE penalty_logs
  ADD CONSTRAINT penalty_logs_penalty_rate_check
    CHECK (penalty_rate >= 0);

ALTER TABLE addresses
  ADD CONSTRAINT addresses_latitude_check
    CHECK (latitude IS NULL OR (latitude BETWEEN -90 AND 90)),
  ADD CONSTRAINT addresses_longitude_check
    CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180));

ALTER TABLE rider_locations
  ADD CONSTRAINT rider_locations_latitude_check
    CHECK (latitude BETWEEN -90 AND 90),
  ADD CONSTRAINT rider_locations_longitude_check
    CHECK (longitude BETWEEN -180 AND 180);

ALTER TABLE application_addresses
  ADD CONSTRAINT application_addresses_latitude_check
    CHECK (latitude IS NULL OR (latitude BETWEEN -90 AND 90)),
  ADD CONSTRAINT application_addresses_longitude_check
    CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180));

-- ─────────────────────────────────────────────────────────────────────────────
-- 6) Partial UNIQUE: at most one ACTIVE assignment per (schedule, rider).
--    Past (failed/completed) assignments stay on file, so a rider can be
--    reassigned after a failed run. collections-assign inserts blindly, so
--    this is the guard that prevents a duplicate active assignment.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE UNIQUE INDEX uq_collection_assignments_active_schedule_rider
  ON collection_assignments (loan_schedule_id, rider_id)
  WHERE status IN ('assigned','accepted','in_progress');

-- ─────────────────────────────────────────────────────────────────────────────
-- 7) Reference tables: updated_at triggers, RLS (read-only for clients),
--    and grants. service_role (edge functions) bypasses RLS to insert into
--    the main tables that reference these codes.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'user_account_statuses','kyc_statuses','loan_statuses','payment_statuses',
    'payment_methods','disbursement_methods','disbursement_statuses',
    'collection_assignment_statuses','credit_investigation_statuses',
    'notification_types','relationship_types','payment_frequencies',
    'address_types','document_types','gender_types','civil_statuses',
    'employment_types','vehicle_types','platform_types','sms_statuses',
    'in_office_application_statuses'
  ] LOOP
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at();',
                   'trg_' || t || '_updated_at', t);
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format('CREATE POLICY %I ON %I FOR SELECT TO anon, authenticated USING (true);',
                   t || '_read', t);
  END LOOP;
END $$;

GRANT SELECT ON ALL TABLES    IN SCHEMA public TO anon, authenticated;
GRANT ALL    ON ALL TABLES    IN SCHEMA public TO service_role;
GRANT ALL    ON ALL SEQUENCES IN SCHEMA public TO service_role;

COMMIT;
