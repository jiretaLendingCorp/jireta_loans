-- 00019_fix_user_delete_fks.sql
-- Allow deleting a user (Auth dashboard / direct delete) without tripping
-- over FK constraints on rows owned by that user.
--
-- These tables hold activity/log rows that belong to the deleted user
-- itself, so they should cascade when the user is removed:
--   auth_logs, sms_logs, terms_consent_logs

ALTER TABLE auth_logs
  DROP CONSTRAINT IF EXISTS auth_logs_user_id_fkey,
  ADD CONSTRAINT auth_logs_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE sms_logs
  DROP CONSTRAINT IF EXISTS sms_logs_user_id_fkey,
  ADD CONSTRAINT sms_logs_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE terms_consent_logs
  DROP CONSTRAINT IF EXISTS terms_consent_logs_user_id_fkey,
  ADD CONSTRAINT terms_consent_logs_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
