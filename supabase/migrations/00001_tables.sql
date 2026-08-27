-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00001_tables.sql
-- Purpose   : Consolidated schema. Extensions, reference (lookup) tables
--             + seeds, all domain tables, constraints, and indexes.
--             Reproduces the end-state of the original 34 migrations
--             (00001_initial_schema .. 00034_remove_blacklist_and_suspend).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─────────────────────────────────────────────────────────────────────
-- 1) Reference (lookup) tables — controlled vocabulary per domain value.
--    Main tables FK to `code` so Postgres enforces the vocabulary while
--    the app layer keeps writing plain strings.
-- ─────────────────────────────────────────────────────────────────────

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

CREATE TABLE account_upgrade_statuses (
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

-- ─────────────────────────────────────────────────────────────────────
-- 1b) Reference seeds (ON CONFLICT keeps this idempotent).
--     NOTE: 'suspended' is intentionally ABSENT (removed end-state).
--     'not_submitted' + 'ci_required' are present (end-state additions).
-- ─────────────────────────────────────────────────────────────────────

INSERT INTO user_account_statuses (code, label, sort_order) VALUES
  ('active',   'Active',   1),
  ('inactive', 'Inactive', 2),
  ('archived', 'Archived', 4);

INSERT INTO account_upgrade_statuses (code, label, sort_order) VALUES
  ('not_submitted', 'Not Submitted', 0),
  ('pending',       'Pending',       1),
  ('submitted',     'Submitted',     2),
  ('verified',      'Verified',      3),
  ('rejected',      'Rejected',      4);

INSERT INTO loan_statuses (code, label, sort_order) VALUES
  ('pending',       'Pending',          1),
  ('account_upgrade_required',  'Account Upgrade Required',     2),
  ('under_review',  'Under Review',     3),
  ('ci_assigned',   'CI Assigned',      4),
  ('ci_completed',  'CI Completed',     5),
  ('approved',      'Approved',         6),
  ('rejected',      'Rejected',         7),
  ('active',        'Active',           8),
  ('completed',     'Completed',        9),
  ('cancelled',     'Cancelled',       10),
  ('overdue',       'Overdue',         11),
  ('ci_required',   'CI Required',     12);

INSERT INTO payment_statuses (code, label, sort_order) VALUES
  ('pending',  'Pending',  1),
  ('verified', 'Verified', 2),
  ('reversed', 'Reversed', 3);

INSERT INTO payment_methods (code, label, sort_order) VALUES
  ('gcash_xendit',    'GCash (Xendit)',   1),
  ('office_cash',     'Office Cash',      2),
  ('rider_collection','Rider Collection', 3);

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
  ('account_upgrade_required',  'Account Upgrade Required',     4),
  ('account_upgrade_submitted', 'Account Upgrade Submitted',    5),
  ('account_upgrade_update',    'Account Upgrade Update',       6),
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

-- ─────────────────────────────────────────────────────────────────────
-- 2) Domain tables
-- ─────────────────────────────────────────────────────────────────────

-- roles
CREATE TABLE roles (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        VARCHAR(50)  NOT NULL UNIQUE CHECK (name IN ('head_manager','employee','rider','lender')),
  description TEXT,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- permissions
CREATE TABLE permissions (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        VARCHAR(100) NOT NULL UNIQUE,
  module      VARCHAR(50)  NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- role_permissions
CREATE TABLE role_permissions (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  role_id       UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(role_id, permission_id)
);

-- users
CREATE TABLE users (
  id                     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  role_id                UUID         NOT NULL REFERENCES roles(id),
  email                  VARCHAR(255) UNIQUE,
  phone_number           VARCHAR(20)  UNIQUE,
  first_name             VARCHAR(100) NOT NULL,
  middle_name            VARCHAR(100),
  last_name              VARCHAR(100) NOT NULL,
  suffix                 VARCHAR(20),
  account_status         VARCHAR(20)  NOT NULL DEFAULT 'active'
                         REFERENCES user_account_statuses(code),
  fcm_token              TEXT,
  force_password_change  BOOLEAN      NOT NULL DEFAULT TRUE,
  terms_accepted_at      TIMESTAMPTZ,
  profile_photo_url      VARCHAR(255),
  last_login_at          TIMESTAMPTZ,
  created_by             UUID REFERENCES users(id),
  created_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  CONSTRAINT users_email_or_phone CHECK (email IS NOT NULL OR phone_number IS NOT NULL)
);

CREATE INDEX idx_users_role_id       ON users(role_id);
CREATE INDEX idx_users_email         ON users(email);
CREATE INDEX idx_users_phone         ON users(phone_number);
CREATE INDEX idx_users_status        ON users(account_status);
CREATE INDEX idx_users_created_by    ON users(created_by);

-- auth_logs
CREATE TABLE auth_logs (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_type      VARCHAR(50) NOT NULL
                  CHECK (event_type IN (
                    'login_success','login_fail','logout','otp_sent','otp_fail',
                    'password_changed','account_locked','password_reset_requested',
                    'session_expired','force_password_changed'
                  )),
  ip_address      INET,
  user_agent      TEXT,
  failed_attempts INT         NOT NULL DEFAULT 0,
  is_locked       BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_auth_logs_user_id    ON auth_logs(user_id);
CREATE INDEX idx_auth_logs_event_type ON auth_logs(event_type);
CREATE INDEX idx_auth_logs_created_at ON auth_logs(created_at);

-- terms_consent_logs
CREATE TABLE terms_consent_logs (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id   VARCHAR(255) NOT NULL,
  platform    VARCHAR(20)  NOT NULL REFERENCES platform_types(code),
  app_version VARCHAR(20)  NOT NULL,
  accepted_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_terms_user_id ON terms_consent_logs(user_id);

-- lender_profiles
CREATE TABLE lender_profiles (
  id                   UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  gender               VARCHAR(10)     REFERENCES gender_types(code),
  civil_status         VARCHAR(20)     REFERENCES civil_statuses(code),
  date_of_birth        DATE,
  employment_type      VARCHAR(30)     REFERENCES employment_types(code),
  employer_name        VARCHAR(255),
  monthly_income       DECIMAL(12,2)   CHECK (monthly_income >= 0),
  gcash_number         VARCHAR(20),
  account_upgrade_status           VARCHAR(20)     NOT NULL DEFAULT 'not_submitted'
                       REFERENCES account_upgrade_statuses(code),
  account_upgrade_rejection_notes  TEXT,
  source_of_funds      VARCHAR(50),
  created_at           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_lender_account_upgrade_status ON lender_profiles(account_upgrade_status);

-- rider_profiles
CREATE TABLE rider_profiles (
  id                       UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  plate_number             VARCHAR(20)  NOT NULL,
  vehicle_type             VARCHAR(50)  NOT NULL REFERENCES vehicle_types(code),
  vehicle_brand            VARCHAR(100),
  drivers_license_number   VARCHAR(50)  NOT NULL,
  drivers_license_expiry   DATE,
  is_available             BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at               TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rider_available ON rider_profiles(is_available);

-- employee_profiles
CREATE TABLE employee_profiles (
  id            UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  position      VARCHAR(100) NOT NULL,
  department    VARCHAR(100),
  hired_at      DATE         NOT NULL,
  gender        VARCHAR(10)  REFERENCES gender_types(code),
  civil_status  VARCHAR(20)  REFERENCES civil_statuses(code),
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- addresses
CREATE TABLE addresses (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  address_type VARCHAR(20)   NOT NULL REFERENCES address_types(code),
  street       VARCHAR(255)  NOT NULL,
  barangay     VARCHAR(100)  NOT NULL,
  city         VARCHAR(100)  NOT NULL,
  province     VARCHAR(100)  NOT NULL,
  zip_code     VARCHAR(10),
  latitude     DECIMAL(10,8),
  longitude    DECIMAL(11,8),
  is_primary   BOOLEAN       NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT addresses_latitude_check
    CHECK (latitude IS NULL OR (latitude BETWEEN -90 AND 90)),
  CONSTRAINT addresses_longitude_check
    CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180))
);

CREATE INDEX idx_addresses_user_id ON addresses(user_id);

-- emergency_contacts
CREATE TABLE emergency_contacts (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  lender_id    UUID         NOT NULL REFERENCES lender_profiles(id) ON DELETE CASCADE,
  name         VARCHAR(255) NOT NULL,
  relationship VARCHAR(50)  NOT NULL REFERENCES relationship_types(code),
  phone_number VARCHAR(20)  NOT NULL,
  address      TEXT,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_emergency_lender_id ON emergency_contacts(lender_id);
-- NOTE: UNIQUE(lender_id) removed in 00105 — replaced by UNIQUE(lender_id, phone_number) for 1:N but no duplicate phone.
CREATE UNIQUE INDEX uq_emergency_contacts_lender_phone ON emergency_contacts(lender_id, phone_number);

-- account_upgrade_documents
CREATE TABLE account_upgrade_documents (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  lender_id        UUID         NOT NULL REFERENCES lender_profiles(id) ON DELETE CASCADE,
  document_type    VARCHAR(50)  NOT NULL REFERENCES document_types(code),
  file_path        TEXT         NOT NULL,
  file_name        VARCHAR(255) NOT NULL,
  file_size        INT          NOT NULL CHECK (file_size > 0),
  mime_type        VARCHAR(100) NOT NULL,
  status           VARCHAR(20)  NOT NULL DEFAULT 'pending'
                   REFERENCES account_upgrade_statuses(code),
  rejection_notes  TEXT,
  reviewed_by      UUID REFERENCES users(id),
  reviewed_at      TIMESTAMPTZ,
  uploaded_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_account_upgrade_docs_lender_id ON account_upgrade_documents(lender_id);
CREATE INDEX idx_account_upgrade_docs_status    ON account_upgrade_documents(status);

-- loans — term_periods/installment_amount added in 00017, backfilled from schedule (00105)
CREATE TABLE loans (
  id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_number              VARCHAR(30)   NOT NULL UNIQUE,
  lender_id                UUID          NOT NULL REFERENCES lender_profiles(id) ON DELETE CASCADE,
  in_office_application_id UUID,
  principal_amount         DECIMAL(12,2) NOT NULL CHECK (principal_amount BETWEEN 3000 AND 500000),
  interest_rate            DECIMAL(5,2)  NOT NULL DEFAULT 20.00,
  payment_frequency        VARCHAR(10)   NOT NULL REFERENCES payment_frequencies(code),
  term_days                INT           NOT NULL CHECK (term_days > 0),
  term_periods             INT           CHECK (term_periods > 0),
  installment_amount       DECIMAL(12,2) CHECK (installment_amount > 0),
  purpose                  TEXT          NOT NULL,
  status                   VARCHAR(30)   NOT NULL DEFAULT 'pending'
                           REFERENCES loan_statuses(code),
  approved_by              UUID REFERENCES users(id),
  rejected_by              UUID REFERENCES users(id),
  rejection_reason         TEXT,
  created_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT loans_interest_rate_check
    CHECK (interest_rate >= 0 AND interest_rate <= 100)
);

CREATE INDEX idx_loans_lender_id    ON loans(lender_id);
CREATE INDEX idx_loans_status       ON loans(status);
CREATE INDEX idx_loans_loan_number  ON loans(loan_number);
CREATE INDEX idx_loans_created_at   ON loans(created_at);

-- loan_schedules
CREATE TABLE loan_schedules (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id            UUID          NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  installment_number INT           NOT NULL CHECK (installment_number > 0),
  due_date           DATE          NOT NULL,
  amount_due         DECIMAL(12,2) NOT NULL CHECK (amount_due > 0),
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE(loan_id, installment_number)
);

CREATE INDEX idx_loan_schedules_loan_id  ON loan_schedules(loan_id);
CREATE INDEX idx_loan_schedules_due_date ON loan_schedules(due_date);

-- co_makers (person entity; link to loans lives in loan_co_makers)
CREATE TABLE co_makers (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  first_name   VARCHAR(100),
  last_name    VARCHAR(100),
  phone_number VARCHAR(20),
  date_of_birth DATE,
  address      TEXT,
  signature    TEXT,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- co_maker_documents
CREATE TABLE co_maker_documents (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  co_maker_id   UUID         NOT NULL REFERENCES co_makers(id) ON DELETE CASCADE,
  document_type VARCHAR(50)  NOT NULL REFERENCES document_types(code),
  file_path     VARCHAR(255) NOT NULL,
  file_name     VARCHAR(255) NOT NULL,
  mime_type     VARCHAR(100) NOT NULL,
  uploaded_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- loan_documents
CREATE TABLE loan_documents (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id       UUID         NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  document_type VARCHAR(50)  NOT NULL REFERENCES document_types(code),
  file_path     VARCHAR(255) NOT NULL,
  file_name     VARCHAR(255) NOT NULL,
  mime_type     VARCHAR(100) NOT NULL,
  uploaded_by   UUID         NOT NULL REFERENCES users(id),
  uploaded_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_loan_docs_loan_id ON loan_documents(loan_id);

-- in_office_applications — loan_id dropped in 00105 (00099) to break circular FK with loans.in_office_application_id
CREATE TABLE in_office_applications (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  lender_id            UUID REFERENCES lender_profiles(id),
  created_by           UUID        NOT NULL REFERENCES users(id),
  wizard_step          INT         NOT NULL DEFAULT 1 CHECK (wizard_step BETWEEN 1 AND 5),
  status               VARCHAR(20) NOT NULL DEFAULT 'draft'
                       REFERENCES in_office_application_statuses(code),
  borrower_signature   TEXT,
  submitted_at         TIMESTAMPTZ,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_in_office_created_by ON in_office_applications(created_by);
CREATE INDEX idx_in_office_status     ON in_office_applications(status);

-- Canonical direction: loans.in_office_application_id -> in_office_applications(id)
-- Reverse lookup: SELECT * FROM loans WHERE in_office_application_id = $app_id
ALTER TABLE loans ADD CONSTRAINT fk_loans_in_office
  FOREIGN KEY (in_office_application_id) REFERENCES in_office_applications(id);

-- credit_investigations
CREATE TABLE credit_investigations (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id        UUID        NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  rider_id       UUID        NOT NULL REFERENCES rider_profiles(id) ON DELETE CASCADE,
  assigned_by    UUID        NOT NULL REFERENCES users(id),
  deadline       TIMESTAMPTZ,
  investigation_notes TEXT,
  status         VARCHAR(20) NOT NULL DEFAULT 'assigned'
                 REFERENCES credit_investigation_statuses(code),
  notes          TEXT,
  report_summary TEXT,
  response_at    TIMESTAMPTZ,
  started_at     TIMESTAMPTZ,
  completed_at   TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ci_loan_id   ON credit_investigations(loan_id);
CREATE INDEX idx_ci_rider_id  ON credit_investigations(rider_id);
CREATE INDEX idx_ci_status    ON credit_investigations(status);

-- ci_documents
CREATE TABLE ci_documents (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ci_id         UUID         NOT NULL REFERENCES credit_investigations(id) ON DELETE CASCADE,
  document_type VARCHAR(50)  NOT NULL REFERENCES document_types(code),
  file_path     VARCHAR(255) NOT NULL,
  file_name     VARCHAR(255) NOT NULL,
  mime_type     VARCHAR(100) NOT NULL,
  latitude      DECIMAL(10,8),
  longitude     DECIMAL(11,8),
  notes         TEXT,
  uploaded_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ci_docs_ci_id ON ci_documents(ci_id);

-- collection_assignments — rider_id/assigned_by nullable for lender-requested 'requested' status (00018); collection_type added in 00019
CREATE TABLE collection_assignments (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_schedule_id    UUID          NOT NULL REFERENCES loan_schedules(id) ON DELETE CASCADE,
  rider_id            UUID          REFERENCES rider_profiles(id),
  assigned_by         UUID          REFERENCES users(id),
  requested_by        UUID          REFERENCES users(id),
  collection_type     VARCHAR(20)   NOT NULL DEFAULT 'rider' CHECK (collection_type IN ('rider','office')),
  collection_schedule TIMESTAMPTZ,
  status              VARCHAR(20)   NOT NULL DEFAULT 'assigned'
                      REFERENCES collection_assignment_statuses(code),
  amount_collected    DECIMAL(12,2) CHECK (amount_collected >= 0),
  collection_notes    TEXT,
  proof_photo         TEXT,
  borrower_signature  TEXT,
  collection_photo    TEXT,
  response_at         TIMESTAMPTZ,
  completed_at        TIMESTAMPTZ,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_coll_assign_rider_id ON collection_assignments(rider_id);
CREATE INDEX idx_coll_assign_status   ON collection_assignments(status);

-- Partial UNIQUE: at most one ACTIVE assignment per (schedule, rider).
CREATE UNIQUE INDEX uq_collection_assignments_active_schedule_rider
  ON collection_assignments (loan_schedule_id, rider_id)
  WHERE status IN ('assigned','accepted','in_progress');

-- disbursements
CREATE TABLE disbursements (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id             UUID          NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  authorized_by       UUID          NOT NULL REFERENCES users(id),
  method              VARCHAR(20)   NOT NULL REFERENCES disbursement_methods(code),
  amount              DECIMAL(12,2) NOT NULL CHECK (amount > 0),
  status              VARCHAR(20)   NOT NULL DEFAULT 'pending'
                      REFERENCES disbursement_statuses(code),
  xendit_id           VARCHAR(255),
  xendit_reference    VARCHAR(255),
  xendit_status       VARCHAR(50),
  rider_id            UUID REFERENCES rider_profiles(id),
  delivery_date       TIMESTAMPTZ,
  delivery_notes      TEXT,
  delivery_proof      TEXT,
  borrower_signature  TEXT,
  disbursed_at        TIMESTAMPTZ,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_disbursements_loan_id ON disbursements(loan_id);
CREATE INDEX idx_disbursements_status  ON disbursements(status);

-- payments — requires at least one FK (enforced by payments_context_check added in 00029 / 00105)
CREATE TABLE payments (
  id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_schedule_id         UUID REFERENCES loan_schedules(id) ON DELETE CASCADE,
  payment_method           VARCHAR(20)   NOT NULL REFERENCES payment_methods(code),
  amount                   DECIMAL(12,2) NOT NULL CHECK (amount > 0),
  status                   VARCHAR(20)   NOT NULL DEFAULT 'pending'
                           REFERENCES payment_statuses(code),
  xendit_payment_id        VARCHAR(255),
  xendit_reference         VARCHAR(255),
  idempotency_key          VARCHAR(255) UNIQUE,
  recorded_by              UUID REFERENCES users(id),
  collection_assignment_id UUID REFERENCES collection_assignments(id),
  receipt_path             VARCHAR(255),
  notes                    TEXT,
  paid_at                  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT payments_context_check CHECK (loan_schedule_id IS NOT NULL OR collection_assignment_id IS NOT NULL)
);

CREATE INDEX idx_payments_status   ON payments(status);
CREATE INDEX idx_payments_paid_at  ON payments(paid_at);
CREATE INDEX idx_payments_idem_key ON payments(idempotency_key);
CREATE INDEX idx_payments_loan_schedule_id ON payments(loan_schedule_id);
CREATE INDEX idx_payments_collection_assignment_id ON payments(collection_assignment_id);

-- payment_reversals — one reversal per payment enforced by UNIQUE(payment_id) in 00105
CREATE TABLE payment_reversals (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  payment_id  UUID        NOT NULL UNIQUE REFERENCES payments(id),
  reversed_by UUID        NOT NULL REFERENCES users(id),
  reason      TEXT        NOT NULL CHECK (char_length(btrim(reason)) > 0),
  reversed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payment_reversals_payment_id ON payment_reversals(payment_id);

-- rider_locations — active_assignment_id / assignment_type dropped in 00035 (dead polymorphic FK)
CREATE TABLE rider_locations (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  rider_id            UUID          NOT NULL UNIQUE REFERENCES rider_profiles(id),
  latitude            DECIMAL(10,8) NOT NULL,
  longitude           DECIMAL(11,8) NOT NULL,
  accuracy            DECIMAL(8,2),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT rider_locations_latitude_check
    CHECK (latitude BETWEEN -90 AND 90),
  CONSTRAINT rider_locations_longitude_check
    CHECK (longitude BETWEEN -180 AND 180)
);

CREATE INDEX idx_rider_locations_rider_id ON rider_locations(rider_id);

-- notifications — read_at added in 00011; client UPDATE restricted to is_read/read_at via trigger in 00105
CREATE TABLE notifications (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id        UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  triggered_by   UUID REFERENCES users(id),
  title          VARCHAR(255) NOT NULL,
  body           TEXT         NOT NULL,
  type           VARCHAR(50)  NOT NULL REFERENCES notification_types(code),
  reference_id   UUID,
  reference_type VARCHAR(50),
  is_read        BOOLEAN     NOT NULL DEFAULT FALSE,
  read_at        TIMESTAMPTZ,
  fcm_sent       BOOLEAN     NOT NULL DEFAULT FALSE,
  sent_at        TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notif_user_id    ON notifications(user_id);
CREATE INDEX idx_notif_is_read    ON notifications(is_read);
CREATE INDEX idx_notif_created_at ON notifications(created_at);
CREATE INDEX idx_notifications_type ON notifications(type);
CREATE INDEX idx_notifications_user_type
  ON notifications(user_id, type, created_at DESC);

-- sms_logs
CREATE TABLE sms_logs (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  loan_schedule_id  UUID REFERENCES loan_schedules(id),
  phone_number      VARCHAR(20)  NOT NULL,
  message           TEXT         NOT NULL,
  status            VARCHAR(20)  NOT NULL DEFAULT 'pending'
                    REFERENCES sms_statuses(code),
  gateway_reference VARCHAR(255),
  sent_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sms_logs_user_id ON sms_logs(user_id);

-- sms_templates
CREATE TABLE sms_templates (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  template_key VARCHAR(100) NOT NULL UNIQUE,
  title        VARCHAR(255) NOT NULL,
  body         TEXT         NOT NULL,
  is_active    BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- reports
CREATE TABLE reports (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  report_type     VARCHAR(100) NOT NULL,
  title           VARCHAR(255) NOT NULL,
  parameters      JSONB        NOT NULL DEFAULT '{}',
  file_path_pdf   VARCHAR(255),
  file_path_excel VARCHAR(255),
  generated_by    UUID         NOT NULL REFERENCES users(id),
  generated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_reports_generated_by ON reports(generated_by);
CREATE INDEX idx_reports_generated_at ON reports(generated_at);

-- report_templates
CREATE TABLE report_templates (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  template_key      VARCHAR(100) NOT NULL UNIQUE,
  title             VARCHAR(255) NOT NULL,
  description       TEXT,
  parameters_schema JSONB        NOT NULL DEFAULT '{}',
  is_active         BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- audit_logs
CREATE TABLE audit_logs (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  performed_by UUID         NOT NULL REFERENCES users(id),
  action       VARCHAR(100) NOT NULL,
  table_name   VARCHAR(100) NOT NULL,
  record_id    UUID         NOT NULL,
  old_values   JSONB,
  new_values   JSONB,
  ip_address   INET,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_performed_by ON audit_logs(performed_by);
CREATE INDEX idx_audit_action       ON audit_logs(action);
CREATE INDEX idx_audit_table_name   ON audit_logs(table_name);
CREATE INDEX idx_audit_created_at   ON audit_logs(created_at);

-- system_config
CREATE TABLE system_config (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  config_key   VARCHAR(100) NOT NULL UNIQUE,
  config_value TEXT         NOT NULL,
  description  TEXT,
  updated_by   UUID REFERENCES users(id),
  updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- penalty_logs
CREATE TABLE penalty_logs (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id       UUID          NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  applied_by    UUID          NOT NULL REFERENCES users(id),
  penalty_basis DECIMAL(12,2) NOT NULL,
  penalty_rate  DECIMAL(5,2)  NOT NULL DEFAULT 20.00,
  penalty_amount DECIMAL(12,2) NOT NULL CHECK (penalty_amount > 0),
  reason        TEXT          NOT NULL,
  applied_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  CONSTRAINT penalty_logs_penalty_rate_check
    CHECK (penalty_rate >= 0)
);

CREATE INDEX idx_penalty_logs_loan_id ON penalty_logs(loan_id);

-- xendit_logs
CREATE TABLE xendit_logs (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id         UUID REFERENCES loans(id) ON DELETE CASCADE,
  payment_id      UUID REFERENCES payments(id),
  disbursement_id UUID REFERENCES disbursements(id),
  event_type      VARCHAR(50)  NOT NULL CHECK (event_type IN ('disbursement','payment','webhook')),
  xendit_id       VARCHAR(255) NOT NULL,
  payload         JSONB        NOT NULL,
  status          VARCHAR(50)  NOT NULL,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_xendit_logs_loan_id ON xendit_logs(loan_id);
CREATE INDEX idx_xendit_logs_type    ON xendit_logs(event_type);

-- otp_codes (rate-limited, expires) — stores SHA-256 hex (64 chars) salted with phone, never plaintext
-- NOTE: deprecated `code` alias was removed in 00106 — only `otp_hash` remains.
CREATE TABLE otp_codes (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  phone_number VARCHAR(20)  NOT NULL,
  otp_hash     TEXT         NOT NULL CHECK (otp_hash ~ '^[0-9a-f]{64}$'),
  attempts     INT          NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  expires_at   TIMESTAMPTZ  NOT NULL,
  used         BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_otp_phone    ON otp_codes(phone_number);
CREATE INDEX idx_otp_expires  ON otp_codes(expires_at);
CREATE INDEX idx_otp_phone_unused ON otp_codes(phone_number) WHERE used = FALSE;

-- password_history (prevent reuse of last 5 passwords)
CREATE TABLE password_history (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  password_hash TEXT        NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_pwd_history_user_id ON password_history(user_id, created_at DESC);

-- rate_limit_logs (internal infra)
CREATE TABLE rate_limit_logs (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  key        TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_rate_limit_key        ON rate_limit_logs(key);
CREATE INDEX idx_rate_limit_created_at ON rate_limit_logs(created_at);

-- password_reset_tokens (internal infra)
CREATE TABLE password_reset_tokens (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT        NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at    TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_pwd_reset_user_id ON password_reset_tokens(user_id);
CREATE INDEX idx_pwd_reset_token   ON password_reset_tokens(token_hash);

-- ─────────────────────────────────────────────────────────────────────
-- 3) 3NF child tables
-- ─────────────────────────────────────────────────────────────────────

-- loan_co_makers (many-to-many: loan <-> co_maker person)
CREATE TABLE loan_co_makers (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id      UUID        NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  co_maker_id  UUID        NOT NULL REFERENCES co_makers(id) ON DELETE CASCADE,
  relationship VARCHAR(50) NOT NULL REFERENCES relationship_types(code),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(loan_id, co_maker_id)
);

CREATE INDEX idx_loan_co_makers_loan_id     ON loan_co_makers(loan_id);
CREATE INDEX idx_loan_co_makers_co_maker_id ON loan_co_makers(co_maker_id);

-- application_personal_info (in-office wizard, step 1; 1:1)
CREATE TABLE application_personal_info (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL UNIQUE REFERENCES in_office_applications(id) ON DELETE CASCADE,
  first_name     VARCHAR(100),
  middle_name    VARCHAR(100),
  last_name      VARCHAR(100),
  phone_number   VARCHAR(20),
  gender         VARCHAR(10)  REFERENCES gender_types(code),
  civil_status   VARCHAR(20)  REFERENCES civil_statuses(code),
  date_of_birth  DATE,
  gcash_number   VARCHAR(20),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_app_personal_info_app_id ON application_personal_info(application_id);

-- application_employment_info (step 1; 1:1)
CREATE TABLE application_employment_info (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id   UUID NOT NULL UNIQUE REFERENCES in_office_applications(id) ON DELETE CASCADE,
  employment_type  VARCHAR(30) REFERENCES employment_types(code),
  employer_name    VARCHAR(255),
  monthly_income   DECIMAL(12,2) CHECK (monthly_income >= 0),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_app_employment_info_app_id ON application_employment_info(application_id);

-- application_addresses (step 2; 1:N)
CREATE TABLE application_addresses (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES in_office_applications(id) ON DELETE CASCADE,
  address_type   VARCHAR(20) REFERENCES address_types(code),
  street         VARCHAR(255),
  barangay       VARCHAR(100),
  city           VARCHAR(100),
  province       VARCHAR(100),
  zip_code       VARCHAR(10),
  latitude       DECIMAL(10,8),
  longitude      DECIMAL(11,8),
  is_primary     BOOLEAN NOT NULL DEFAULT FALSE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT application_addresses_latitude_check
    CHECK (latitude IS NULL OR (latitude BETWEEN -90 AND 90)),
  CONSTRAINT application_addresses_longitude_check
    CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180))
);
CREATE INDEX idx_app_addresses_app_id ON application_addresses(application_id);

-- application_emergency_contacts (step 2; 1:N)
CREATE TABLE application_emergency_contacts (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES in_office_applications(id) ON DELETE CASCADE,
  name           VARCHAR(255),
  relationship   VARCHAR(50) REFERENCES relationship_types(code),
  phone_number   VARCHAR(20),
  address        TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_app_emergency_contacts_app ON application_emergency_contacts(application_id);

-- application_loan_details (step 3; 1:1)
CREATE TABLE application_loan_details (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id   UUID NOT NULL UNIQUE REFERENCES in_office_applications(id) ON DELETE CASCADE,
  principal_amount DECIMAL(12,2) CHECK (principal_amount BETWEEN 3000 AND 500000),
  interest_rate    DECIMAL(5,2)  NOT NULL DEFAULT 20.00,
  payment_frequency VARCHAR(10) REFERENCES payment_frequencies(code),
  term_days        INT CHECK (term_days > 0),
  purpose          TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT application_loan_details_interest_rate_check
    CHECK (interest_rate >= 0 AND interest_rate <= 100)
);
CREATE INDEX idx_app_loan_details_app_id ON application_loan_details(application_id);

-- application_co_makers (step 4; 1:N)
CREATE TABLE application_co_makers (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES in_office_applications(id) ON DELETE CASCADE,
  first_name     VARCHAR(100),
  last_name      VARCHAR(100),
  relationship   VARCHAR(50) REFERENCES relationship_types(code),
  phone_number   VARCHAR(20),
  date_of_birth  DATE,
  address        TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_app_co_makers_app_id ON application_co_makers(application_id);

-- application_documents (step 5; 1:N)
CREATE TABLE application_documents (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES in_office_applications(id) ON DELETE CASCADE,
  document_type  VARCHAR(50) REFERENCES document_types(code),
  file_path      TEXT,
  file_name      VARCHAR(255),
  mime_type      VARCHAR(100),
  uploaded_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_app_documents_app_id ON application_documents(application_id);

-- ─────────────────────────────────────────────────────────────────────
-- 4) Disbursement preference (borrower's preferred release method; 1:1)
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE loan_disbursement_preferences (
  loan_id     UUID PRIMARY KEY REFERENCES loans(id) ON DELETE CASCADE,
  method      VARCHAR(20) NOT NULL REFERENCES disbursement_methods(code),
  account     VARCHAR(255),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_loan_disb_prefs_loan_id ON loan_disbursement_preferences(loan_id);

COMMIT;
