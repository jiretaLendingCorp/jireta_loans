-- supabase/migrations/00009_credit_investigations_rider_fk.sql
-- Deleting a user cascades into rider_profiles (rider_profiles.id -> users.id
-- ON DELETE CASCADE). credit_investigations.rider_id references rider_profiles
-- without any ON DELETE action, so removing a rider/user fails with
-- 'credit_investigations_rider_id_fkey' violations. Give the relation the same
-- cascade behavior so rider deletions clean up their credit investigations.

ALTER TABLE credit_investigations
  DROP CONSTRAINT credit_investigations_rider_id_fkey;

ALTER TABLE credit_investigations
  ADD CONSTRAINT credit_investigations_rider_id_fkey
    FOREIGN KEY (rider_id) REFERENCES rider_profiles(id) ON DELETE CASCADE;
