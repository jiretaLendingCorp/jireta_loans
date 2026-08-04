-- supabase/migrations/00008_employee_profile_fields.sql
-- Adds gender / civil_status to employee_profiles so the full set of data the
-- head manager enters when creating an employee is actually persisted.

ALTER TABLE employee_profiles
  ADD COLUMN IF NOT EXISTS gender        VARCHAR(10),
  ADD COLUMN IF NOT EXISTS civil_status  VARCHAR(20);

-- Keep the same check values used by lender_profiles.
ALTER TABLE employee_profiles
  DROP CONSTRAINT IF EXISTS employee_profiles_gender_check,
  DROP CONSTRAINT IF EXISTS employee_profiles_civil_status_check;

ALTER TABLE employee_profiles
  ADD CONSTRAINT employee_profiles_gender_check
    CHECK (gender IS NULL OR gender IN ('male','female','other')),
  ADD CONSTRAINT employee_profiles_civil_status_check
    CHECK (civil_status IS NULL OR civil_status IN ('single','married','widowed','separated'));
