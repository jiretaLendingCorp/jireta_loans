-- /supabase/migrations/00022_3nf_co_makers_in_office_applications.sql
-- 3NF normalization pass — part 2.
--
-- 1) co_makers: split the mixed "person + loan relationship" table into
--    a person entity (co_makers) and a many-to-many loan link
--    (loan_co_makers). co_maker_documents keeps referencing co_makers(id)
--    (the person) so document history is preserved.
-- 2) in_office_applications: replace the five denormalized wizard JSONB
--    columns (step1_data..step5_data) with relational child tables so each
--    step's data is queryable, indexable, and referentially intact while
--    still supporting a multi-step draft workflow via the parent
--    (wizard_step / status) + child rows keyed by application_id.
--
-- NOTE ON ORDERING: the existing co_makers_read policy (00017) references
-- co_makers.loan_id, so it must be dropped/recreated before the column is
-- dropped. The parent in_office_applications keeps wizard_step, status,
-- borrower_signature, submitted_at, loan_id, lender_id, created_by.

BEGIN;

SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) co_makers → person entity + loan_co_makers relationship table
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE loan_co_makers (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id      UUID        NOT NULL REFERENCES loans(id) ON DELETE CASCADE,
  co_maker_id  UUID        NOT NULL REFERENCES co_makers(id) ON DELETE CASCADE,
  relationship VARCHAR(50) NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(loan_id, co_maker_id)
);

CREATE INDEX idx_loan_co_makers_loan_id    ON loan_co_makers(loan_id);
CREATE INDEX idx_loan_co_makers_co_maker_id ON loan_co_makers(co_maker_id);

-- Backfill: every existing co_makers row is one person + one loan link.
-- Person ids are preserved 1:1 so co_maker_documents.co_maker_id stays valid.
INSERT INTO loan_co_makers (loan_id, co_maker_id, relationship, created_at)
SELECT loan_id, id, relationship, created_at
FROM co_makers
WHERE loan_id IS NOT NULL;

-- Co-maker signature belongs to the person (00013 added it to co_makers).
ALTER TABLE co_makers
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE TRIGGER trg_co_makers_updated_at
  BEFORE UPDATE ON co_makers FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- RLS: replace the old policy that referenced co_makers.loan_id (dropped below).
DROP POLICY IF EXISTS "co_makers_read" ON co_makers;

CREATE POLICY "co_makers_read" ON co_makers
  FOR SELECT TO authenticated
  USING (
    id IN (
      SELECT lcm.co_maker_id FROM loan_co_makers lcm
      WHERE lcm.loan_id IN (SELECT auth_own_loan_ids())
    )
    OR auth_role() IN ('head_manager','employee')
  );

-- The relationship moves to loan_co_makers.
DROP INDEX IF EXISTS idx_co_makers_loan_id;

ALTER TABLE co_makers
  DROP CONSTRAINT IF EXISTS co_makers_loan_id_fkey,
  DROP COLUMN IF EXISTS loan_id,
  DROP COLUMN IF EXISTS relationship;

-- RLS on the new relationship table.
ALTER TABLE loan_co_makers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "loan_co_makers_read" ON loan_co_makers
  FOR SELECT TO authenticated
  USING (
    loan_id IN (SELECT auth_own_loan_ids())
    OR auth_role() IN ('head_manager','employee')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) in_office_applications → relational child tables
-- ─────────────────────────────────────────────────────────────────────────────

-- 2a) Lender identity captured in step 1 (1:1)
CREATE TABLE application_personal_info (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL UNIQUE REFERENCES in_office_applications(id) ON DELETE CASCADE,
  first_name     VARCHAR(100),
  middle_name    VARCHAR(100),
  last_name      VARCHAR(100),
  phone_number   VARCHAR(20),
  gender         VARCHAR(10),
  civil_status   VARCHAR(20),
  date_of_birth  DATE,
  gcash_number   VARCHAR(20),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2b) Employment info captured in step 1 (1:1)
CREATE TABLE application_employment_info (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id   UUID NOT NULL UNIQUE REFERENCES in_office_applications(id) ON DELETE CASCADE,
  employment_type  VARCHAR(30),
  employer_name    VARCHAR(255),
  monthly_income   DECIMAL(12,2) CHECK (monthly_income >= 0),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2c) Addresses captured in step 2 (1:N)
CREATE TABLE application_addresses (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES in_office_applications(id) ON DELETE CASCADE,
  address_type   VARCHAR(20) CHECK (address_type IN ('home','work','provincial')),
  street         VARCHAR(255),
  barangay       VARCHAR(100),
  city           VARCHAR(100),
  province       VARCHAR(100),
  zip_code       VARCHAR(10),
  latitude       DECIMAL(10,8),
  longitude      DECIMAL(11,8),
  is_primary     BOOLEAN NOT NULL DEFAULT FALSE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2d) Emergency contacts captured in step 2 (1:N)
CREATE TABLE application_emergency_contacts (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES in_office_applications(id) ON DELETE CASCADE,
  name           VARCHAR(255),
  relationship   VARCHAR(50),
  phone_number   VARCHAR(20),
  address        TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2e) Loan terms captured in step 3 (1:1)
CREATE TABLE application_loan_details (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id   UUID NOT NULL UNIQUE REFERENCES in_office_applications(id) ON DELETE CASCADE,
  principal_amount DECIMAL(12,2) CHECK (principal_amount BETWEEN 3000 AND 500000),
  interest_rate    DECIMAL(5,2)  NOT NULL DEFAULT 20.00,
  payment_frequency VARCHAR(10) CHECK (payment_frequency IN ('daily','weekly','monthly')),
  term_days        INT CHECK (term_days > 0),
  purpose          TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2f) Co-maker captured in step 4 (1:N, draft-time person snapshot)
CREATE TABLE application_co_makers (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES in_office_applications(id) ON DELETE CASCADE,
  first_name     VARCHAR(100),
  last_name      VARCHAR(100),
  relationship   VARCHAR(50),
  phone_number   VARCHAR(20),
  date_of_birth  DATE,
  address        TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2g) Documents uploaded in step 5 (1:N)
CREATE TABLE application_documents (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES in_office_applications(id) ON DELETE CASCADE,
  document_type  VARCHAR(50),
  file_path      TEXT,
  file_name      VARCHAR(255),
  mime_type      VARCHAR(100),
  uploaded_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_app_personal_info_app_id   ON application_personal_info(application_id);
CREATE INDEX idx_app_employment_info_app_id ON application_employment_info(application_id);
CREATE INDEX idx_app_addresses_app_id       ON application_addresses(application_id);
CREATE INDEX idx_app_emergency_contacts_app ON application_emergency_contacts(application_id);
CREATE INDEX idx_app_loan_details_app_id    ON application_loan_details(application_id);
CREATE INDEX idx_app_co_makers_app_id       ON application_co_makers(application_id);
CREATE INDEX idx_app_documents_app_id       ON application_documents(application_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2h) Data migration: JSONB wizard columns → child tables (best-effort).
--     Guards against NULL/empty payloads so an empty draft stays empty.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO application_personal_info
  (application_id, first_name, middle_name, last_name, phone_number,
   gender, civil_status, date_of_birth, gcash_number)
SELECT
  id,
  step1_data->>'first_name',
  step1_data->>'middle_name',
  step1_data->>'last_name',
  COALESCE(step1_data->>'phone_number', step1_data->>'phone'),
  step1_data->>'gender',
  step1_data->>'civil_status',
  NULLIF(step1_data->>'date_of_birth', '')::date,
  step1_data->>'gcash_number'
FROM in_office_applications
WHERE step1_data IS NOT NULL AND step1_data <> '{}'::jsonb;

INSERT INTO application_employment_info
  (application_id, employment_type, employer_name, monthly_income)
SELECT
  id,
  step1_data->>'employment_type',
  step1_data->>'employer_name',
  NULLIF(step1_data->>'monthly_income', '')::decimal
FROM in_office_applications
WHERE step1_data IS NOT NULL AND step1_data <> '{}'::jsonb;

INSERT INTO application_addresses
  (application_id, address_type, street, barangay, city, province, zip_code,
   latitude, longitude, is_primary)
SELECT
  a.id,
  addr->>'address_type',
  addr->>'street',
  addr->>'barangay',
  addr->>'city',
  addr->>'province',
  addr->>'zip_code',
  NULLIF(addr->>'latitude', '')::decimal,
  NULLIF(addr->>'longitude', '')::decimal,
  COALESCE((addr->>'is_primary')::boolean, FALSE)
FROM in_office_applications a
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(a.step2_data->'addresses', '[]'::jsonb)) addr
WHERE a.step2_data IS NOT NULL AND a.step2_data <> '{}'::jsonb;

INSERT INTO application_emergency_contacts
  (application_id, name, relationship, phone_number, address)
SELECT
  a.id,
  ec->>'name',
  ec->>'relationship',
  ec->>'phone_number',
  ec->>'address'
FROM in_office_applications a
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(a.step2_data->'emergency_contacts', '[]'::jsonb)) ec
WHERE a.step2_data IS NOT NULL AND a.step2_data <> '{}'::jsonb;

INSERT INTO application_loan_details
  (application_id, principal_amount, interest_rate, payment_frequency, term_days, purpose)
SELECT
  id,
  NULLIF(step3_data->>'principal_amount', '')::decimal,
  COALESCE(NULLIF(step3_data->>'interest_rate', '')::decimal, 20.00),
  step3_data->>'frequency',
  NULLIF(step3_data->>'term_days', '')::int,
  step3_data->>'purpose'
FROM in_office_applications
WHERE step3_data IS NOT NULL AND step3_data <> '{}'::jsonb;

INSERT INTO application_co_makers
  (application_id, first_name, last_name, relationship, phone_number, date_of_birth, address)
SELECT
  id,
  step4_data->>'first_name',
  step4_data->>'last_name',
  step4_data->>'relationship',
  step4_data->>'contact_number',
  NULLIF(step4_data->>'birthday', '')::date,
  step4_data->>'address'
FROM in_office_applications
WHERE step4_data IS NOT NULL AND step4_data <> '{}'::jsonb;

INSERT INTO application_documents
  (application_id, document_type, file_path, file_name, mime_type, uploaded_at)
SELECT
  a.id,
  d->>'document_type',
  d->>'file_url',
  d->>'file_name',
  d->>'mime_type',
  NOW()
FROM in_office_applications a
CROSS JOIN LATERAL (
  SELECT d FROM jsonb_array_elements(COALESCE(a.step4_data->'documents', '[]'::jsonb)) d
  UNION ALL
  SELECT d FROM jsonb_array_elements(COALESCE(a.step5_data->'documents', '[]'::jsonb)) d
) d
WHERE (a.step4_data IS NOT NULL AND a.step4_data <> '{}'::jsonb)
   OR (a.step5_data IS NOT NULL AND a.step5_data <> '{}'::jsonb);

-- Drop the denormalized wizard JSONB columns now that data is migrated.
ALTER TABLE in_office_applications
  DROP COLUMN IF EXISTS step1_data,
  DROP COLUMN IF EXISTS step2_data,
  DROP COLUMN IF EXISTS step3_data,
  DROP COLUMN IF EXISTS step4_data,
  DROP COLUMN IF EXISTS step5_data;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2i) RLS on child tables — mirror the parent's in_office_read policy
--     (creator or head_manager). service_role (edge functions) bypasses RLS.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION application_owner(application_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT created_by FROM in_office_applications WHERE id = application_id
$$;

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
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY;', tbl);
    policy_name := tbl || '_read';
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR SELECT TO authenticated
       USING (application_owner(application_id) = auth.uid()
              OR auth_role() = ''head_manager'');',
      policy_name, tbl);
  END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Grants (mirror 00007; covers tables created in this migration)
-- ─────────────────────────────────────────────────────────────────────────────
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT ALL PRIVILEGES ON ALL ROUTINES  IN SCHEMA public TO service_role;
GRANT SELECT ON ALL TABLES    IN SCHEMA public TO anon, authenticated;
GRANT USAGE  ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;

COMMIT;
