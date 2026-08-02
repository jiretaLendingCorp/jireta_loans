-- /supabase/migrations/00001_initial_schema.sql
-- Jireta Loans & Credit Corp 1966 — Complete Database Schema

BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.1 roles
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE roles (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        VARCHAR(50)  NOT NULL UNIQUE CHECK (name IN ('head_manager','employee','rider','lender')),
  description TEXT,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.2 permissions
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE permissions (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        VARCHAR(100) NOT NULL UNIQUE,
  module      VARCHAR(50)  NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.3 role_permissions
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE role_permissions (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  role_id       UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(role_id, permission_id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.4 users
-- ─────────────────────────────────────────────────────────────────────────────
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
                         CHECK (account_status IN ('active','inactive','suspended','archived')),
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.5 auth_logs
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE auth_logs (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID        NOT NULL REFERENCES users(id),
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.6 terms_consent_logs
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE terms_consent_logs (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID         NOT NULL REFERENCES users(id),
  device_id   VARCHAR(255) NOT NULL,
  platform    VARCHAR(20)  NOT NULL CHECK (platform IN ('ios','android','web')),
  app_version VARCHAR(20)  NOT NULL,
  accepted_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_terms_user_id ON terms_consent_logs(user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.7 lender_profiles
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE lender_profiles (
  id                   UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  gender               VARCHAR(10)     CHECK (gender IN ('male','female','other')),
  civil_status         VARCHAR(20)     CHECK (civil_status IN ('single','married','widowed','separated')),
  date_of_birth        DATE,
  employment_type      VARCHAR(30)     CHECK (employment_type IN ('employed','self_employed','unemployed','student')),
  employer_name        VARCHAR(255),
  monthly_income       DECIMAL(12,2)   CHECK (monthly_income >= 0),
  gcash_number         VARCHAR(20),
  kyc_status           VARCHAR(20)     NOT NULL DEFAULT 'pending'
                       CHECK (kyc_status IN ('pending','submitted','verified','rejected')),
  kyc_rejection_notes  TEXT,
  is_blacklisted       BOOLEAN         NOT NULL DEFAULT FALSE,
  blacklist_reason     TEXT,
  blacklisted_by       UUID REFERENCES users(id),
  blacklisted_at       TIMESTAMPTZ,
  created_at           TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_lender_kyc_status     ON lender_profiles(kyc_status);
CREATE INDEX idx_lender_blacklisted    ON lender_profiles(is_blacklisted);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.8 rider_profiles
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE rider_profiles (
  id                       UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  plate_number             VARCHAR(20)  NOT NULL,
  vehicle_type             VARCHAR(50)  NOT NULL CHECK (vehicle_type IN ('Motorcycle','Bicycle','Car')),
  vehicle_brand            VARCHAR(100),
  drivers_license_number   VARCHAR(50)  NOT NULL,
  drivers_license_expiry   DATE,
  is_available             BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at               TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rider_available ON rider_profiles(is_available);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.9 employee_profiles
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE employee_profiles (
  id         UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  position   VARCHAR(100) NOT NULL,
  department VARCHAR(100),
  hired_at   DATE         NOT NULL,
  created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.10 addresses
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE addresses (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  address_type VARCHAR(20)   NOT NULL CHECK (address_type IN ('home','work','provincial')),
  street       VARCHAR(255)  NOT NULL,
  barangay     VARCHAR(100)  NOT NULL,
  city         VARCHAR(100)  NOT NULL,
  province     VARCHAR(100)  NOT NULL,
  zip_code     VARCHAR(10),
  latitude     DECIMAL(10,8),
  longitude    DECIMAL(11,8),
  is_primary   BOOLEAN       NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_addresses_user_id ON addresses(user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.11 emergency_contacts
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE emergency_contacts (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  lender_id    UUID         NOT NULL REFERENCES lender_profiles(id) ON DELETE CASCADE,
  name         VARCHAR(255) NOT NULL,
  relationship VARCHAR(50)  NOT NULL,
  phone_number VARCHAR(20)  NOT NULL,
  address      TEXT,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_emergency_lender_id ON emergency_contacts(lender_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.12 kyc_documents
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE kyc_documents (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  lender_id        UUID         NOT NULL REFERENCES lender_profiles(id) ON DELETE CASCADE,
  document_type    VARCHAR(50)  NOT NULL
                   CHECK (document_type IN ('valid_id','proof_of_income','barangay_clearance','pay_slip','selfie','proof_of_billing','other')),
  file_path        VARCHAR(255) NOT NULL,
  file_name        VARCHAR(255) NOT NULL,
  file_size        INT          NOT NULL CHECK (file_size > 0),
  mime_type        VARCHAR(100) NOT NULL,
  status           VARCHAR(20)  NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','verified','rejected')),
  rejection_notes  TEXT,
  reviewed_by      UUID REFERENCES users(id),
  reviewed_at      TIMESTAMPTZ,
  uploaded_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_kyc_docs_lender_id ON kyc_documents(lender_id);
CREATE INDEX idx_kyc_docs_status    ON kyc_documents(status);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.13 loans
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE loans (
  id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_number              VARCHAR(30)   NOT NULL UNIQUE,
  lender_id                UUID          NOT NULL REFERENCES lender_profiles(id),
  in_office_application_id UUID,
  principal_amount         DECIMAL(12,2) NOT NULL CHECK (principal_amount BETWEEN 3000 AND 500000),
  interest_rate            DECIMAL(5,2)  NOT NULL DEFAULT 20.00,
  total_payable            DECIMAL(12,2) NOT NULL,
  payment_frequency        VARCHAR(10)   NOT NULL CHECK (payment_frequency IN ('daily','weekly','monthly')),
  term_days                INT           NOT NULL CHECK (term_days > 0),
  outstanding_balance      DECIMAL(12,2) NOT NULL CHECK (outstanding_balance >= 0),
  purpose                  TEXT          NOT NULL,
  status                   VARCHAR(30)   NOT NULL DEFAULT 'pending'
                           CHECK (status IN (
                             'pending','kyc_required','under_review','ci_assigned',
                             'ci_completed','approved','rejected','active','completed',
                             'cancelled','overdue'
                           )),
  approved_by              UUID REFERENCES users(id),
  rejected_by              UUID REFERENCES users(id),
  rejection_reason         TEXT,
  disbursed_at             TIMESTAMPTZ,
  disbursement_method      VARCHAR(20) CHECK (disbursement_method IN ('gcash','office_cash','rider_delivery')),
  xendit_disbursement_id   VARCHAR(255),
  penalty_applied          BOOLEAN       NOT NULL DEFAULT FALSE,
  penalty_amount           DECIMAL(12,2) CHECK (penalty_amount >= 0),
  penalty_applied_at       TIMESTAMPTZ,
  penalty_applied_by       UUID REFERENCES users(id),
  created_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_loans_lender_id    ON loans(lender_id);
CREATE INDEX idx_loans_status       ON loans(status);
CREATE INDEX idx_loans_loan_number  ON loans(loan_number);
CREATE INDEX idx_loans_created_at   ON loans(created_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.14 loan_schedules
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE loan_schedules (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id            UUID          NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  installment_number INT           NOT NULL CHECK (installment_number > 0),
  due_date           DATE          NOT NULL,
  amount_due         DECIMAL(12,2) NOT NULL CHECK (amount_due > 0),
  amount_paid        DECIMAL(12,2) NOT NULL DEFAULT 0.00 CHECK (amount_paid >= 0),
  status             VARCHAR(20)   NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending','partial','paid','overdue')),
  paid_at            TIMESTAMPTZ,
  created_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE(loan_id, installment_number)
);

CREATE INDEX idx_loan_schedules_loan_id  ON loan_schedules(loan_id);
CREATE INDEX idx_loan_schedules_due_date ON loan_schedules(due_date);
CREATE INDEX idx_loan_schedules_status   ON loan_schedules(status);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.15 co_makers
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE co_makers (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id      UUID         NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  first_name   VARCHAR(100) NOT NULL,
  last_name    VARCHAR(100) NOT NULL,
  relationship VARCHAR(50)  NOT NULL,
  phone_number VARCHAR(20)  NOT NULL,
  date_of_birth DATE,
  address      TEXT         NOT NULL,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_co_makers_loan_id ON co_makers(loan_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.16 co_maker_documents
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE co_maker_documents (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  co_maker_id   UUID         NOT NULL REFERENCES co_makers(id) ON DELETE CASCADE,
  document_type VARCHAR(50)  NOT NULL,
  file_path     VARCHAR(255) NOT NULL,
  file_name     VARCHAR(255) NOT NULL,
  mime_type     VARCHAR(100) NOT NULL,
  uploaded_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.17 loan_documents
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE loan_documents (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id       UUID         NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  document_type VARCHAR(50)  NOT NULL,
  file_path     VARCHAR(255) NOT NULL,
  file_name     VARCHAR(255) NOT NULL,
  mime_type     VARCHAR(100) NOT NULL,
  uploaded_by   UUID         NOT NULL REFERENCES users(id),
  uploaded_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_loan_docs_loan_id ON loan_documents(loan_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.18 in_office_applications
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE in_office_applications (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  lender_id            UUID REFERENCES lender_profiles(id),
  created_by           UUID        NOT NULL REFERENCES users(id),
  wizard_step          INT         NOT NULL DEFAULT 1 CHECK (wizard_step BETWEEN 1 AND 5),
  step1_data           JSONB,
  step2_data           JSONB,
  step3_data           JSONB,
  step4_data           JSONB,
  step5_data           JSONB,
  status               VARCHAR(20) NOT NULL DEFAULT 'draft'
                       CHECK (status IN ('draft','submitted','converted')),
  loan_id              UUID REFERENCES loans(id),
  borrower_signature   VARCHAR(255),
  submitted_at         TIMESTAMPTZ,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_in_office_created_by ON in_office_applications(created_by);
CREATE INDEX idx_in_office_status     ON in_office_applications(status);

-- Add FK after loans table created
ALTER TABLE loans ADD CONSTRAINT fk_loans_in_office
  FOREIGN KEY (in_office_application_id) REFERENCES in_office_applications(id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.19 credit_investigations
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE credit_investigations (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id        UUID        NOT NULL REFERENCES loans(id),
  rider_id       UUID        NOT NULL REFERENCES rider_profiles(id),
  assigned_by    UUID        NOT NULL REFERENCES users(id),
  deadline       TIMESTAMPTZ,
  investigation_notes TEXT,
  status         VARCHAR(20) NOT NULL DEFAULT 'assigned'
                 CHECK (status IN ('assigned','accepted','declined','in_progress','completed')),
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.20 ci_documents
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE ci_documents (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ci_id         UUID         NOT NULL REFERENCES credit_investigations(id) ON DELETE CASCADE,
  document_type VARCHAR(50)  NOT NULL
                CHECK (document_type IN ('ci_photo','evidence','site_photo','neighbor_interview','proof_of_residence','other')),
  file_path     VARCHAR(255) NOT NULL,
  file_name     VARCHAR(255) NOT NULL,
  mime_type     VARCHAR(100) NOT NULL,
  latitude      DECIMAL(10,8),
  longitude     DECIMAL(11,8),
  notes         TEXT,
  uploaded_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ci_docs_ci_id ON ci_documents(ci_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.21 collection_assignments
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE collection_assignments (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_schedule_id    UUID          NOT NULL REFERENCES loan_schedules(id),
  loan_id             UUID          NOT NULL REFERENCES loans(id),
  rider_id            UUID          NOT NULL REFERENCES rider_profiles(id),
  assigned_by         UUID          NOT NULL REFERENCES users(id),
  collection_schedule TIMESTAMPTZ,
  status              VARCHAR(20)   NOT NULL DEFAULT 'assigned'
                      CHECK (status IN ('assigned','accepted','declined','in_progress','completed','failed')),
  amount_collected    DECIMAL(12,2) CHECK (amount_collected >= 0),
  collection_notes    TEXT,
  proof_photo         VARCHAR(255),
  borrower_signature  VARCHAR(255),
  collection_photo    VARCHAR(255),
  response_at         TIMESTAMPTZ,
  completed_at        TIMESTAMPTZ,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_coll_assign_loan_id  ON collection_assignments(loan_id);
CREATE INDEX idx_coll_assign_rider_id ON collection_assignments(rider_id);
CREATE INDEX idx_coll_assign_status   ON collection_assignments(status);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.22 disbursements
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE disbursements (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id             UUID          NOT NULL REFERENCES loans(id),
  authorized_by       UUID          NOT NULL REFERENCES users(id),
  method              VARCHAR(20)   NOT NULL CHECK (method IN ('gcash','office_cash','rider_delivery')),
  amount              DECIMAL(12,2) NOT NULL CHECK (amount > 0),
  status              VARCHAR(20)   NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','processing','completed','failed')),
  xendit_id           VARCHAR(255),
  xendit_reference    VARCHAR(255),
  xendit_status       VARCHAR(50),
  rider_id            UUID REFERENCES rider_profiles(id),
  delivery_date       TIMESTAMPTZ,
  delivery_notes      TEXT,
  delivery_proof      VARCHAR(255),
  borrower_signature  VARCHAR(255),
  disbursed_at        TIMESTAMPTZ,
  created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_disbursements_loan_id ON disbursements(loan_id);
CREATE INDEX idx_disbursements_status  ON disbursements(status);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.23 payments
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE payments (
  id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id                  UUID          NOT NULL REFERENCES loans(id),
  loan_schedule_id         UUID REFERENCES loan_schedules(id),
  payment_method           VARCHAR(20)   NOT NULL
                           CHECK (payment_method IN ('gcash_xendit','office_cash','rider_collection')),
  amount                   DECIMAL(12,2) NOT NULL CHECK (amount > 0),
  status                   VARCHAR(20)   NOT NULL DEFAULT 'pending'
                           CHECK (status IN ('pending','verified','reversed')),
  xendit_payment_id        VARCHAR(255),
  xendit_reference         VARCHAR(255),
  idempotency_key          VARCHAR(255) UNIQUE,
  recorded_by              UUID REFERENCES users(id),
  collection_assignment_id UUID REFERENCES collection_assignments(id),
  receipt_path             VARCHAR(255),
  notes                    TEXT,
  paid_at                  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  created_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payments_loan_id  ON payments(loan_id);
CREATE INDEX idx_payments_status   ON payments(status);
CREATE INDEX idx_payments_paid_at  ON payments(paid_at);
CREATE INDEX idx_payments_idem_key ON payments(idempotency_key);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.24 payment_reversals
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE payment_reversals (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  payment_id  UUID        NOT NULL REFERENCES payments(id),
  reversed_by UUID        NOT NULL REFERENCES users(id),
  reason      TEXT        NOT NULL,
  reversed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payment_reversals_payment_id ON payment_reversals(payment_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.25 blacklist
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE blacklist (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  lender_id  UUID        NOT NULL UNIQUE REFERENCES lender_profiles(id),
  reason     TEXT        NOT NULL,
  added_by   UUID        NOT NULL REFERENCES users(id),
  added_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  removed_by UUID REFERENCES users(id),
  removed_at TIMESTAMPTZ,
  is_active  BOOLEAN     NOT NULL DEFAULT TRUE
);

CREATE INDEX idx_blacklist_lender_id ON blacklist(lender_id);
CREATE INDEX idx_blacklist_is_active ON blacklist(is_active);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.26 rider_locations
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE rider_locations (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  rider_id            UUID          NOT NULL UNIQUE REFERENCES rider_profiles(id),
  active_assignment_id UUID,
  assignment_type     VARCHAR(20)   CHECK (assignment_type IN ('collection','ci','disbursement')),
  latitude            DECIMAL(10,8) NOT NULL,
  longitude           DECIMAL(11,8) NOT NULL,
  accuracy            DECIMAL(8,2),
  updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rider_locations_rider_id ON rider_locations(rider_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.27 notifications
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE notifications (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id        UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  triggered_by   UUID REFERENCES users(id),
  title          VARCHAR(255) NOT NULL,
  body           TEXT         NOT NULL,
  type           VARCHAR(50)  NOT NULL
                 CHECK (type IN (
                   'loan_status','kyc_status','ci_assigned','collection_assigned',
                   'payment_received','disbursement_sent','system','otp','penalty_applied',
                   'blacklist','password_change','assignment_accepted','assignment_declined'
                 )),
  reference_id   UUID,
  reference_type VARCHAR(50),
  is_read        BOOLEAN     NOT NULL DEFAULT FALSE,
  fcm_sent       BOOLEAN     NOT NULL DEFAULT FALSE,
  sent_at        TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notif_user_id    ON notifications(user_id);
CREATE INDEX idx_notif_is_read    ON notifications(is_read);
CREATE INDEX idx_notif_created_at ON notifications(created_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.28 sms_logs
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE sms_logs (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           UUID         NOT NULL REFERENCES users(id),
  loan_schedule_id  UUID REFERENCES loan_schedules(id),
  phone_number      VARCHAR(20)  NOT NULL,
  message           TEXT         NOT NULL,
  status            VARCHAR(20)  NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('sent','failed','pending')),
  gateway_reference VARCHAR(255),
  sent_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sms_logs_user_id ON sms_logs(user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.29 sms_templates
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE sms_templates (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  template_key VARCHAR(100) NOT NULL UNIQUE,
  title        VARCHAR(255) NOT NULL,
  body         TEXT         NOT NULL,
  is_active    BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.30 reports
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.31 report_templates
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE report_templates (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  template_key      VARCHAR(100) NOT NULL UNIQUE,
  title             VARCHAR(255) NOT NULL,
  description       TEXT,
  parameters_schema JSONB        NOT NULL DEFAULT '{}',
  is_active         BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.32 audit_logs
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.33 system_config
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE system_config (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  config_key   VARCHAR(100) NOT NULL UNIQUE,
  config_value TEXT         NOT NULL,
  description  TEXT,
  updated_by   UUID REFERENCES users(id),
  updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.34 penalty_logs
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE penalty_logs (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id       UUID          NOT NULL REFERENCES loans(id),
  applied_by    UUID          NOT NULL REFERENCES users(id),
  penalty_basis DECIMAL(12,2) NOT NULL,
  penalty_rate  DECIMAL(5,2)  NOT NULL DEFAULT 20.00,
  penalty_amount DECIMAL(12,2) NOT NULL CHECK (penalty_amount > 0),
  reason        TEXT          NOT NULL,
  applied_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_penalty_logs_loan_id ON penalty_logs(loan_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3.35 xendit_logs
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE xendit_logs (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id         UUID REFERENCES loans(id),
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

-- ─────────────────────────────────────────────────────────────────────────────
-- OTP Storage (rate-limited, expires)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE otp_codes (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  phone_number VARCHAR(20)  NOT NULL,
  code         VARCHAR(6)   NOT NULL,
  attempts     INT          NOT NULL DEFAULT 0,
  expires_at   TIMESTAMPTZ  NOT NULL,
  used         BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_otp_phone    ON otp_codes(phone_number);
CREATE INDEX idx_otp_expires  ON otp_codes(expires_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- Password History (prevent reuse of last 5 passwords)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE password_history (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  password_hash TEXT        NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_pwd_history_user_id ON password_history(user_id, created_at DESC);

-- ─────────────────────────────────────────────────────────────────────────────
-- Auto-update updated_at trigger function
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_lender_updated_at
  BEFORE UPDATE ON lender_profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_rider_updated_at
  BEFORE UPDATE ON rider_profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_employee_updated_at
  BEFORE UPDATE ON employee_profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_addresses_updated_at
  BEFORE UPDATE ON addresses FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_loans_updated_at
  BEFORE UPDATE ON loans FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_loan_schedules_updated_at
  BEFORE UPDATE ON loan_schedules FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_in_office_updated_at
  BEFORE UPDATE ON in_office_applications FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_ci_updated_at
  BEFORE UPDATE ON credit_investigations FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_collection_updated_at
  BEFORE UPDATE ON collection_assignments FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_disbursements_updated_at
  BEFORE UPDATE ON disbursements FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMIT;