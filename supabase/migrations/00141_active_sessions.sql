-- =====================================================================
-- Migration : 00141_active_sessions.sql
-- Purpose   : Enforce one active Supabase session per public user account.
--             The access token remains owned by Supabase Auth; this table
--             stores only the server-side session identifier and timestamps.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

CREATE TABLE IF NOT EXISTS public.active_sessions (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  session_identifier    TEXT NOT NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now_manila(),
  last_seen_at          TIMESTAMPTZ NOT NULL DEFAULT now_manila(),
  revoked_at            TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_active_sessions_session_identifier
  ON public.active_sessions(session_identifier);
CREATE INDEX IF NOT EXISTS idx_active_sessions_user_last_seen
  ON public.active_sessions(user_id, last_seen_at);

ALTER TABLE public.active_sessions ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.active_sessions FROM PUBLIC;

-- The Edge Functions use the service-role client for these SECURITY DEFINER
-- operations. No client role can read or mutate the table directly.
CREATE OR REPLACE FUNCTION public.claim_active_session(
  p_user_id UUID,
  p_session_identifier TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF p_user_id IS NULL OR p_session_identifier IS NULL
     OR btrim(p_session_identifier) = '' THEN
    RETURN FALSE;
  END IF;

  -- Mark the previous session as revoked before replacing it. The UNIQUE
  -- user_id constraint serializes concurrent claims for the same account;
  -- the last committed successful login is the active one.
  UPDATE public.active_sessions
  SET revoked_at = now_manila(),
      last_seen_at = now_manila()
  WHERE user_id = p_user_id
    AND session_identifier IS DISTINCT FROM p_session_identifier
    AND revoked_at IS NULL;

  INSERT INTO public.active_sessions (
    user_id, session_identifier, created_at, last_seen_at, revoked_at
  )
  VALUES (
    p_user_id, p_session_identifier, now_manila(), now_manila(), NULL
  )
  ON CONFLICT (user_id) DO UPDATE
  SET session_identifier = EXCLUDED.session_identifier,
      created_at = EXCLUDED.created_at,
      last_seen_at = EXCLUDED.last_seen_at,
      revoked_at = NULL;

  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_active_session(
  p_user_id UUID,
  p_session_identifier TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  matched_count INTEGER;
BEGIN
  UPDATE public.active_sessions
  SET last_seen_at = now_manila()
  WHERE user_id = p_user_id
    AND session_identifier = p_session_identifier
    AND revoked_at IS NULL;

  GET DIAGNOSTICS matched_count = ROW_COUNT;
  RETURN matched_count > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_active_session(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.validate_active_session(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_active_session(UUID, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.validate_active_session(UUID, TEXT) TO service_role;

-- Keep the report catalog aligned with the system's LENDER terminology and
-- the templates the UI actually exposes. `account_upgrade_report` was listed
-- in the report library but had no active template row, so generating it
-- always returned "Report template is not active".
UPDATE public.report_templates
SET title = 'Lender Report',
    description = 'Registered lender accounts with account status and verification status'
WHERE template_key = 'lender_report';

INSERT INTO public.report_templates (template_key, title, description, parameters_schema)
VALUES (
  'account_upgrade_report',
  'Account Upgrade Report',
  'Lender account upgrade submissions and verification status',
  '{"date_from":{"type":"date","optional":true},"date_to":{"type":"date","optional":true}}'
)
ON CONFLICT (template_key) DO UPDATE
SET title = EXCLUDED.title,
    description = EXCLUDED.description,
    is_active = TRUE;

-- Guard: any legacy catalog rows still using the obsolete borrower label are
-- re-labelled Lender so the user-facing wording is consistent everywhere.
UPDATE public.report_templates
SET title = 'Lender Report',
    description = 'Registered lender accounts with account status and verification status'
WHERE template_key = 'borrower_report';

COMMIT;
