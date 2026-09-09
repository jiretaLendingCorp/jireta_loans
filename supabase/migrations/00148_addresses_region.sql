-- 00148: add `region` to addresses — the Account Upgrade Residence step now
-- uses cascading Region → Province → City/Municipality → Barangay dropdowns
-- and stores the selected region alongside province/city/barangay.

ALTER TABLE addresses
  ADD COLUMN IF NOT EXISTS region VARCHAR(100);