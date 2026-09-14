-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00164_collection_schedule_end.sql
-- Purpose   : Kapag nag-a-assign ng rider para sa collection, dapat
--             "From – To" ang oras ng rider visit (hindi lang isang oras).
--
--   Ang `collection_assignments.collection_schedule` (TIMESTAMPTZ) ang
--   simula ng window. Idinadagdag ng migration na ito ang
--   `collection_schedule_end` para sa katapusan ng window. Ang expiry logic
--   (00114 / 00127) ay nananatiling naka-base sa `collection_schedule`.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

ALTER TABLE collection_assignments
  ADD COLUMN IF NOT EXISTS collection_schedule_end TIMESTAMPTZ;

COMMENT ON COLUMN collection_assignments.collection_schedule_end IS
  'Katapusan ng rider visit window. Ang collection_schedule ang simula — "From – To" ang iskedyul na nakikita ng rider/lender.';

COMMIT;
