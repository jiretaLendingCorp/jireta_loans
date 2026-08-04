-- supabase/migrations/00011_blacklist_lender_fk.sql
-- Deleting a user cascades into lender_profiles (lender_profiles.id -> users.id
-- ON DELETE CASCADE). blacklist.lender_id references lender_profiles without any
-- ON DELETE action, so removing a blacklisted lender/user fails with a
-- 'blacklist_lender_id_fkey' violation. The blacklist entry is lender-owned, so
-- it is removed together with the lender (lender_id is NOT NULL, so SET NULL is
-- not an option).

ALTER TABLE blacklist
  DROP CONSTRAINT blacklist_lender_id_fkey;
ALTER TABLE blacklist
  ADD CONSTRAINT blacklist_lender_id_fkey
    FOREIGN KEY (lender_id) REFERENCES lender_profiles(id) ON DELETE CASCADE;