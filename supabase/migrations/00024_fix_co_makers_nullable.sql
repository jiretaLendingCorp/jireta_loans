-- /supabase/migrations/00024_fix_co_makers_nullable.sql
-- co_makers is now a person entity populated from two sources:
--   • loans-apply  (mobile lender app)  — phone_number/address passed as null
--     when the borrower omits them
--   • in-office-submit (walk-in wizard) — copies from application_co_makers,
--     whose phone_number/address/date_of_birth/first_name/last_name are
--     nullable draft fields
-- The columns were NOT NULL (from 00001), so either path fails with a
-- NOT NULL violation whenever a co-maker lacks optional details. Relax them
-- to match the draft source of truth (application_co_makers is nullable).

BEGIN;

ALTER TABLE co_makers
  ALTER COLUMN first_name    DROP NOT NULL,
  ALTER COLUMN last_name     DROP NOT NULL,
  ALTER COLUMN phone_number  DROP NOT NULL,
  ALTER COLUMN address       DROP NOT NULL;

COMMIT;
