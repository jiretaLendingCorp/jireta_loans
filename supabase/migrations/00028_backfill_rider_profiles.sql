-- ═══════════════════════════════════════════════════════════════════════════
-- Jireta Loans & Credit Corp 1966
-- Migration: 00028_backfill_rider_profiles.sql
-- Purpose  : Backfill rider_profiles for any rider user that was created
--            without one (legacy/test data). Riders are filtered by
--            `rider_profiles.is_available` in the assign-rider UI, so a rider
--            without a profile row is invisible to staff ("No available rider")
--            and can never be assigned a credit investigation.
--            Placeholder vehicle/plate/license values are used so the rider
--            becomes assignable; the rider can correct them in their profile.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

INSERT INTO rider_profiles (id, plate_number, vehicle_type, vehicle_brand,
                            drivers_license_number, is_available)
SELECT
  u.id,
  'TMP-' || right(substring(u.phone_number from '\d+'), 8),
  'Motorcycle',
  NULL,
  'N/A-' || substring(u.phone_number from '\d+'),
  TRUE
FROM users u
JOIN roles r ON r.id = u.role_id
WHERE r.name = 'rider'
  AND NOT EXISTS (SELECT 1 FROM rider_profiles rp WHERE rp.id = u.id);

COMMIT;
