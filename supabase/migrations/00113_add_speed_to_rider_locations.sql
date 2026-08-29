-- 00113_add_speed_to_rider_locations.sql
-- Store rider's actual GPS speed (km/h) alongside lat/lng so lenders can
-- display real speed instead of derived distance/time estimate.
-- Conversion: km/h = metersPerSecond * 3.6 (handled in app & edge function).
-- Invalid/negative speeds are stored as NULL and shown as --.

ALTER TABLE public.rider_locations
  ADD COLUMN IF NOT EXISTS speed_kmh DECIMAL(6,2) CHECK (speed_kmh IS NULL OR (speed_kmh >= 0 AND speed_kmh <= 120));

COMMENT ON COLUMN public.rider_locations.speed_kmh IS 'Rider GPS speed in km/h (m/s * 3.6). NULL when unavailable/invalid.';
