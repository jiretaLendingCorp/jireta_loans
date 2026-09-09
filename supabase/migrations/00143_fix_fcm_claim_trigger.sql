-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00143_fix_fcm_claim_trigger.sql
-- Purpose   : Repair the FCM push channel. The guard
--             enforce_notifications_update_columns() (00002/00105) raises
--             an exception for ANY change to notifications.fcm_sent, but
--             the shared FCM dispatcher (notifications.ts claimNotification
--             / claimPendingNotifications) marks rows as pushed via
--                 UPDATE notifications SET fcm_sent = true ...
--             That UPDATE always hit the guard → the claim failed →
--             every FCM device push silently died (only the in-app
--             Realtime notification row was delivered). As a result riders /
--             lenders / staff never received device notifications for CI
--             assignments, loan approvals, overdue collections, etc.
--
--             Fix: allow fcm_sent (+ sent_at) to change when the UPDATE is
--             performed server-side. Every PostgREST request connects as
--             session_user 'authenticator', then SET ROLEs to 'anon' /
--             'authenticated' (client JWTs) or 'postgres' (service role /
--             edge functions). current_user therefore cleanly separates the
--             two: clients stay locked to is_read/read_at while the FCM
--             claim goes through.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

CREATE OR REPLACE FUNCTION public.enforce_notifications_update_columns()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_is_server boolean;
BEGIN
  -- Service-role (edge function) requests run as current_user = 'postgres';
  -- mobile/web clients run as 'anon' / 'authenticated'.
  v_is_server := current_user NOT IN ('anon', 'authenticated');

  IF v_is_server THEN
    -- Server side: only the FCM claim fields may change; everything else
    -- stays frozen (protects against accidental clobbering).
    IF NEW.user_id        IS DISTINCT FROM OLD.user_id
       OR NEW.triggered_by IS DISTINCT FROM OLD.triggered_by
       OR NEW.title         IS DISTINCT FROM OLD.title
       OR NEW.body          IS DISTINCT FROM OLD.body
       OR NEW.type          IS DISTINCT FROM OLD.type
       OR NEW.reference_id  IS DISTINCT FROM OLD.reference_id
       OR NEW.reference_type IS DISTINCT FROM OLD.reference_type
       OR NEW.created_at    IS DISTINCT FROM OLD.created_at
       OR NEW.id            IS DISTINCT FROM OLD.id
    THEN
      RAISE EXCEPTION 'notifications: server updates may only change fcm_sent / sent_at'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    -- Client (PostgREST) side: only is_read and read_at may change.
    IF NEW.user_id        IS DISTINCT FROM OLD.user_id
       OR NEW.triggered_by IS DISTINCT FROM OLD.triggered_by
       OR NEW.title         IS DISTINCT FROM OLD.title
       OR NEW.body          IS DISTINCT FROM OLD.body
       OR NEW.type          IS DISTINCT FROM OLD.type
       OR NEW.reference_id  IS DISTINCT FROM OLD.reference_id
       OR NEW.reference_type IS DISTINCT FROM OLD.reference_type
       OR NEW.fcm_sent      IS DISTINCT FROM OLD.fcm_sent
       OR NEW.sent_at       IS DISTINCT FROM OLD.sent_at
       OR NEW.created_at    IS DISTINCT FROM OLD.created_at
       OR NEW.id            IS DISTINCT FROM OLD.id
    THEN
      RAISE EXCEPTION 'notifications: only is_read and read_at may be updated by client'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Re-attach the trigger so the updated function takes effect.
DROP TRIGGER IF EXISTS trg_enforce_notifications_update_columns ON public.notifications;
CREATE TRIGGER trg_enforce_notifications_update_columns
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.enforce_notifications_update_columns();

COMMENT ON FUNCTION public.enforce_notifications_update_columns() IS
  'Server-side (service role) updates may flip fcm_sent/sent_at for the FCM claim; clients are restricted to is_read/read_at.';

COMMIT;