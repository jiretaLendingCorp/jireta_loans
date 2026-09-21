-- =====================================================================
-- Jireta Loans & Credit Corp
-- Migration : 00171_auth_last_login_real_utc.sql
-- Purpose   : Isang orasan lang para sa `users.last_login_at`.
--
-- Problema:
--   Sa 00120, ang `fn_auth_update_last_login()` trigger ay ginawang
--   `now_manila()` — isang Manila wall-clock na NAKA-LABEL na UTC, kaya
--   WALONG ORAS SA HINAHARAP ng tunay na instant.
--
--   Ang lahat ng ibang writers ng `last_login_at` ay TUNAY na UTC:
--     * Edge Functions (`auth-login` / `auth-otp` / `auth-google`) —
--       `nowManilaISO()` / `new Date().toISOString()`.
--     * Legacy rows — `DEFAULT NOW()` ng column.
--
--   Dahil dito, kapag ang `auth_logs` (login_success) row ay na-insert at
--   WALANG kasunod na explicit update, Manila-wall-as-UTC ang naiiwan.
--   Kapag dumaan iyon sa `parseManila()` ng app (+8h, dahil totoong UTC
--   ang inaasahan), 16 oras na mali ang naipapakitang "Last login".
--
-- Ayos (katulad ng 00156 para sa `active_sessions.last_seen_at`):
--   1) TUNAY na instant (`NOW()`) na lang ang isinusulat ng trigger —
--      pareho na sa Edge Functions at sa `parseManila()` ng app.
--   2) Backfill: ang mga row na naiwang nakasulat ng trigger ay tiyak na
--      nasa hinaharap (> NOW()) dahil +8h sila; ibinabalik ang 8 oras.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ── 1) Trigger — NOW() (tunay na UTC instant) ─────────────────────────
-- Tandaan: ang `auth_logs.created_at` ay `DEFAULT NOW()` rin, kaya pareho
-- sila ng orasan (at ang explicit update ng Edge Functions pagkatapos ng
-- insert ang siyang huling nananaig sa normal na login path).
CREATE OR REPLACE FUNCTION public.fn_auth_update_last_login()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE users
  SET last_login_at = NOW()
  WHERE id = NEW.user_id;
  RETURN NEW;
END;
$$;

-- ── 2) Backfill — tanggalin ang +8h na naipasok ng luma trigger ───────
-- Tanging ang `now_manila()` ang kayang magsulat ng timestamp na nasa
-- hinaharap, kaya ito lang ang tina-target (1 minute tolerance).
UPDATE users
SET last_login_at = last_login_at - INTERVAL '8 hours'
WHERE last_login_at > NOW() + INTERVAL '1 minute';

COMMIT;
