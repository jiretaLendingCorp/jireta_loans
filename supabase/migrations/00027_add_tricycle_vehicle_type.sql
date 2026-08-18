-- Add Tricycle to vehicle_types so the rider creation form's dropdown option
-- ('tricycle') maps to a valid rider_profiles.vehicle_type FK code.
INSERT INTO vehicle_types (code, label, sort_order)
VALUES ('Tricycle', 'Tricycle', 4)
ON CONFLICT (code) DO NOTHING;