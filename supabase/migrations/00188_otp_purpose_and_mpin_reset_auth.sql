-- =====================================================================
-- Jireta Loans & Credit Corp
-- Migration : 00188_otp_purpose_and_mpin_reset_auth.sql
-- Purpose   :
--   1) Bigyan ng `purpose` ang `otp_codes` para hindi magamit ang OTP ng
--      isang flow (hal. login) sa ibang flow (hal. reset ng MPIN).
--   2) Gumawa ng `mpin_reset_authorizations` — server-issued, short-lived,
--      single-use na permiso para mag-reset ng MPIN. Ito lang ang
--      tinatanggap ng `auth-mpin?fn=set|reset`; HINDI pinaniniwalaan ang
--      frontend flag na `isVerified`.
--
-- Seguridad:
--   * Ang table ay may RLS na naka-enable at WALANG policy + revoked grants
--     sa anon/authenticated. Tanging ang Edge Functions (service role) ang
--     makakabasa/makakasulat, kaya hindi ito nakikita ng app sa PostgREST.
--   * Ang token na ipinapadala sa app ay random (256-bit). Ang naka-store
--     lang ay ang SHA-256 hash nito, kaya kahit ma-leak ang DB ay hindi ito
--     mai-replay.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ── 1) otp_codes.purpose ─────────────────────────────────────────────
ALTER TABLE public.otp_codes
  ADD COLUMN IF NOT EXISTS purpose TEXT NOT NULL DEFAULT 'login';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_otp_codes_purpose'
      AND conrelid = 'public.otp_codes'::regclass
  ) THEN
    ALTER TABLE public.otp_codes
      ADD CONSTRAINT chk_otp_codes_purpose
      CHECK (purpose IN ('login', 'reset_mpin'));
  END IF;
END;
$$;

COMMENT ON COLUMN public.otp_codes.purpose IS
  'Para saan ang OTP: login (pagpasok) o reset_mpin (pag-reset ng MPIN).';

-- Mas mabilis na paghahanap ng pinakabagong active na OTP ng isang numero.
CREATE INDEX IF NOT EXISTS idx_otp_phone_purpose_created
  ON public.otp_codes(phone_number, purpose, created_at DESC);

-- ── 2) mpin_reset_authorizations ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.mpin_reset_authorizations (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  -- SHA-256 hex ng token. Ito lang ang naka-store, hindi ang token mismo.
  token_hash   TEXT        NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  -- Ang numerong na-verify ng OTP (para sa audit; hindi ito ang credential).
  phone_number VARCHAR(20) NOT NULL,
  purpose      TEXT        NOT NULL DEFAULT 'reset_mpin'
                           CHECK (purpose IN ('reset_mpin')),
  -- Bilang ng maling pagtatangka na gamitin ang token.
  attempts     INT         NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  expires_at   TIMESTAMPTZ NOT NULL,
  used_at      TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.mpin_reset_authorizations            IS
  'Short-lived, single-use na server-side authorization para sa MPIN reset — galing sa OTP na may purpose=reset_mpin.';
COMMENT ON COLUMN public.mpin_reset_authorizations.token_hash IS
  'SHA-256 hex ng opaque reset token. Hindi kailanman naka-store ang token mismo.';

CREATE INDEX IF NOT EXISTS idx_mpin_reset_auth_user_id
  ON public.mpin_reset_authorizations(user_id);
CREATE INDEX IF NOT EXISTS idx_mpin_reset_auth_expires
  ON public.mpin_reset_authorizations(expires_at);
CREATE INDEX IF NOT EXISTS idx_mpin_reset_auth_active
  ON public.mpin_reset_authorizations(user_id)
  WHERE used_at IS NULL;

ALTER TABLE public.mpin_reset_authorizations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.mpin_reset_authorizations FROM anon, authenticated;

-- Kapag may bagong authorization ang isang user, isara na ang mga lumang
-- hindi pa nagamit — isang active na token lang dapat sa isang pagkakataon.
CREATE OR REPLACE FUNCTION public.fn_mpin_reset_auth_invalidate_previous()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.mpin_reset_authorizations
  SET    used_at = NOW()
  WHERE  user_id   = NEW.user_id
    AND  id       <> NEW.id
    AND  used_at IS NULL;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mpin_reset_auth_invalidate_previous
  ON public.mpin_reset_authorizations;
CREATE TRIGGER trg_mpin_reset_auth_invalidate_previous
  AFTER INSERT ON public.mpin_reset_authorizations
  FOR EACH ROW EXECUTE FUNCTION public.fn_mpin_reset_auth_invalidate_previous();

-- ── 3) Housekeeping ─────────────────────────────────────────────────
-- Ang mga lumang token ay walang silbi na pagkatapos ng `expires_at`.
-- Isang araw pa silang itinatago para may audit trail bago burahin.
CREATE OR REPLACE FUNCTION public.cleanup_expired_mpin_reset_authorizations()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  DELETE FROM public.mpin_reset_authorizations
  WHERE created_at < NOW() - INTERVAL '1 day';
END;
$$;

COMMIT;
