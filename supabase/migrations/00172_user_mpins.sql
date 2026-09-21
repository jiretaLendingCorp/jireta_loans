-- =====================================================================
-- Jireta Loans & Credit Corp
-- Migration : 00172_user_mpins.sql
-- Purpose   : Server-side (ACCOUNT-level) 4-digit MPIN para sa rider / lender.
--
-- Bakit:
--   Dating LOCAL-only ang MPIN: ang hash (SHA-256 + salt) ay nasa secure
--   storage ng device lang, at hindi kailanman ipinapadala sa server. Bunga:
--     * hindi ito nadadala sa bagong phone — kailangang i-setup muli,
--     * hindi ito kilala ng account (device lang ang may alam), at
--     * ang pag-restore ng session pagkatapos ng MPIN unlock ay gumagawa ng
--       "stub" user sa auth state (walang pangalan), na siyang dahilan kung
--       bakit lumalabas pa rin ang one-time Terms & Conditions / Fill In
--       Information para sa isang account na matagal nang kumpleto.
--
--   Ngayon: ang `user_mpins` ang source of truth. Ang verification ay
--   server-side (kasama ang attempts/lockout at ang 10-palit-sa-15-araw na
--   limitasyon), kaya pareho ang MPIN sa lahat ng device ng account.
--
-- Seguridad:
--   * `mpin_hash` = `sha256$<hex>` ng `jireta::<user_id>::<mpin>` (tingnan ang
--     `_shared/password_hash.ts`) — hindi kailanman plain text.
--   * RLS na naka-enable na WALANG policy + revoked grants sa anon/authenticated
--     → tanging ang Edge Functions (service role) ang makakabasa/makakasulat.
--     Hindi ito nakikita ng app sa pamamagitan ng PostgREST.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

CREATE TABLE IF NOT EXISTS public.user_mpins (
  user_id             UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  -- `sha256$<hex>` — one-way digest, salted ng user id (hindi mai-replay).
  mpin_hash           TEXT        NOT NULL,
  -- Sunod-sunod na maling MPIN (nire-reset kapag tama o pagkatapos ng lockout).
  failed_attempts     INTEGER     NOT NULL DEFAULT 0,
  -- Pansamantalang lockout pagkatapos maubos ang attempts.
  locked_until        TIMESTAMPTZ,
  -- 15-araw na window para sa 10-palit na limitasyon.
  change_window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  change_count        INTEGER     NOT NULL DEFAULT 0,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.user_mpins                    IS 'Account-level 4-digit MPIN para sa rider / lender (server-side verification).';
COMMENT ON COLUMN public.user_mpins.mpin_hash          IS 'sha256$<hex> ng jireta::<user_id>::<mpin>. Hindi kailanman plain text.';
COMMENT ON COLUMN public.user_mpins.change_window_start IS 'Simula ng kasalukuyang 15-araw na window ng MPIN changes.';
COMMENT ON COLUMN public.user_mpins.change_count       IS 'Bilang ng pagpalit sa loob ng window (max 10 bawat 15 araw).';

-- ── RLS: deny-by-default (Edge Functions lang ang may access) ─────────
ALTER TABLE public.user_mpins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_mpins FROM anon, authenticated;

-- ── updated_at ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_user_mpins_touch()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_mpins_touch ON public.user_mpins;
CREATE TRIGGER trg_user_mpins_touch
  BEFORE UPDATE ON public.user_mpins
  FOR EACH ROW EXECUTE FUNCTION public.fn_user_mpins_touch();

COMMIT;
