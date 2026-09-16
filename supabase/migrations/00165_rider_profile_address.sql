-- 00165: rider address.
-- The Create Rider form now captures a full Philippine address. The structured
-- parts live in `addresses` (3NF, see users-create insertPrimaryAddress), while
-- this column keeps the composed one-line address on the rider profile itself
-- so rider-facing screens can show it without joining `addresses`.

ALTER TABLE rider_profiles
  ADD COLUMN IF NOT EXISTS address TEXT;

COMMENT ON COLUMN rider_profiles.address IS
  'Composed one-line address captured on rider creation (structured parts also in addresses).';
