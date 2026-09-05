-- =====================================================================
-- Migration: 00126_fcm_device_tokens.sql
-- Purpose  : Multi-device FCM push support on top of the EXISTING
--            notification system.
--
--   What stays (source of truth, untouched):
--     - notifications table + realtime in-app channel
--     - sendPushNotification() / notifyStaff() edge-function helpers
--     - notifications-send / notifications-view edge functions
--
--   What this adds:
--     1) user_devices      — one row per (user, device FCM token).
--        users.fcm_token (legacy single-token column) is backfilled into
--        this table and kept in sync going forward; user_devices is the
--        authoritative multi-device store.
--     2) RLS               — authenticated users may SELECT their own
--        devices only; ALL writes happen through edge functions
--        (service_role), matching the project's thin-client rule.
--     3) enforce_notifications_update_columns — service_role may now flip
--        fcm_sent / sent_at (claim-based duplicate prevention). Client
--        restriction (is_read/read_at only) is unchanged.
--     4) pg_net trigger    — DB-created notifications (e.g. overdue
--        expiry inserts from expire_overdue_assignments) are enqueued to
--        the notifications-push edge function so they ALSO become device
--        pushes. Guarded: if pg_net or the function URL config is
--        missing, the trigger no-ops and nothing breaks.
--
--   Duplicate prevention (claim model):
--     Edge-function flows insert the notification row, atomically claim it
--     (UPDATE ... SET fcm_sent = true WHERE fcm_sent = false RETURNING *),
--     then send FCM. The pg_net trigger only enqueues rows still carrying
--     fcm_sent = false. Exactly one claimant wins per row, so the same
--     notification can never be pushed twice.
--
--   Idempotent: safe to re-run.
-- =====================================================================

BEGIN;
SET search_path = public, extensions;

-- ─────────────────────────────────────────────────────────────────────
-- 1) user_devices — authoritative multi-device FCM token store
-- ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_devices (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  fcm_token     TEXT NOT NULL,
  platform      VARCHAR(20) NOT NULL DEFAULT 'android'
                REFERENCES platform_types(code),
  app_version   VARCHAR(50),
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  last_seen_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT user_devices_token_not_blank CHECK (btrim(fcm_token) <> ''),
  CONSTRAINT user_devices_token_length   CHECK (char_length(fcm_token) <= 4096),
  UNIQUE (user_id, fcm_token)
);

CREATE INDEX IF NOT EXISTS idx_user_devices_user_active
  ON user_devices(user_id) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_user_devices_token
  ON user_devices(fcm_token);

DROP TRIGGER IF EXISTS trg_user_devices_updated_at ON user_devices;
CREATE TRIGGER trg_user_devices_updated_at
  BEFORE UPDATE ON user_devices
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMENT ON TABLE user_devices IS
  'One row per (user, device) FCM token — enables multiple devices per authenticated user. '
  'Authoritative store for push delivery; users.fcm_token is the legacy single-token column kept in sync. '
  'Writes only via service_role edge functions (device-tokens register/unregister, auth-logout); '
  'authenticated users may SELECT their own rows only.';

-- ─────────────────────────────────────────────────────────────────────
-- 2) RLS — SELECT own devices; writes stay service_role-only
-- ─────────────────────────────────────────────────────────────────────
ALTER TABLE user_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_devices_select_own ON user_devices;
CREATE POLICY user_devices_select_own ON user_devices
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

COMMENT ON POLICY user_devices_select_own ON user_devices IS
  'Authenticated users may list their own devices. No INSERT/UPDATE/DELETE policies: '
  'all writes go through edge functions with service_role (device-tokens, auth-logout).';

-- Backfill legacy single tokens so previously-registered devices keep
-- receiving pushes after this migration.
INSERT INTO user_devices (user_id, fcm_token, platform, is_active, created_at, updated_at)
SELECT u.id, u.fcm_token, 'android', TRUE, NOW(), NOW()
FROM users u
WHERE u.fcm_token IS NOT NULL AND btrim(u.fcm_token) <> ''
ON CONFLICT (user_id, fcm_token) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────
-- 3) Allow service_role to update notification delivery metadata
--    (fcm_sent / sent_at) for the claim-based duplicate prevention.
--    Client-side column restriction (is_read / read_at only) is kept.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_notifications_update_columns()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Edge functions (service_role) may update delivery metadata such as
  -- fcm_sent / sent_at when claiming a notification for push dispatch.
  IF auth.role() = 'service_role' THEN
    RETURN NEW;
  END IF;

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
    RAISE EXCEPTION 'notifications: only is_read and read_at may be updated by client' USING ERRCODE='42501';
  END IF;
  IF OLD.is_read = TRUE AND NEW.is_read = FALSE THEN
    RAISE EXCEPTION 'notifications: cannot mark notification as unread' USING ERRCODE='42501';
  END IF;
  IF NEW.is_read = TRUE AND OLD.is_read = FALSE AND NEW.read_at IS NULL THEN
    NEW.read_at := NOW();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_notifications_update_columns ON public.notifications;
CREATE TRIGGER trg_enforce_notifications_update_columns
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.enforce_notifications_update_columns();

-- ─────────────────────────────────────────────────────────────────────
-- 4) pg_net trigger — DB-created notifications (fcm_sent = false) are
--    enqueued to the notifications-push edge function so they also
--    arrive as device pushes. Fully guarded: missing pg_net or a
--    placeholder function URL just skips the enqueue (in-app/Realtime
--    delivery is unaffected).
-- ─────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_net;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg_net not available — DB-triggered push enqueue disabled (edge-function inline pushes still work)';
  END;
END $$;

CREATE OR REPLACE FUNCTION fn_notification_enqueue_push()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_url     TEXT;
  v_secret  TEXT;
BEGIN
  -- Inline sends (edge functions) claim their own row; only untouched rows
  -- are candidates for the webhook path.
  IF NEW.fcm_sent THEN
    RETURN NEW;
  END IF;

  SELECT config_value INTO v_url    FROM system_config WHERE config_key = 'push_function_url';
  SELECT config_value INTO v_secret FROM system_config WHERE config_key = 'push_function_secret';

  IF v_url IS NULL OR v_url = '' OR v_url LIKE '%REPLACE_ME%' THEN
    RETURN NEW; -- not configured yet — no-op
  END IF;

  BEGIN
    PERFORM net.http_post(
      url := v_url || '?fn=send&id=' || NEW.id::text,
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'x-push-secret', v_secret
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 5000
    );
  EXCEPTION WHEN OTHERS THEN
    -- Never fail the notification insert because the push enqueue hiccuped.
    RAISE WARNING 'notification push enqueue failed for %: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notification_enqueue_push ON notifications;
CREATE TRIGGER trg_notification_enqueue_push
  AFTER INSERT ON notifications
  FOR EACH ROW
  WHEN (NEW.fcm_sent = false)
  EXECUTE FUNCTION fn_notification_enqueue_push();

COMMENT ON FUNCTION fn_notification_enqueue_push() IS
  'Enqueues DB-created notifications (fcm_sent = false) to the notifications-push edge function via pg_net '
  'so overdue/system notifications also become device pushes. Uses push_function_url / push_function_secret '
  'from system_config; no-ops until both are configured. Edge-function inline sends claim fcm_sent at insert '
  'time, so the trigger never double-sends.';

-- ─────────────────────────────────────────────────────────────────────
-- 5) system_config seeds for the webhook path
--    (HM can also edit these in Settings → System config values)
-- ─────────────────────────────────────────────────────────────────────
INSERT INTO system_config (config_key, config_value, description)
VALUES (
  'push_function_url',
  'https://lcelzrvpqwlbeccrwpkp.supabase.co/functions/v1/notifications-push',
  'URL of the notifications-push edge function used by the pg_net trigger to enqueue push sends. Replace REPLACE_ME with your Supabase project ref (e.g. https://lcelzrvpqwlbeccrwpkp.supabase.co/functions/v1/notifications-push).'
), (
  'push_function_secret',
  'REPLACE_ME',
  'Shared secret sent as header x-push-secret when the pg_net trigger calls notifications-push. Must match the PUSH_WEBHOOK_SECRET env var of that edge function.'
)
ON CONFLICT (config_key) DO NOTHING;

COMMIT;
