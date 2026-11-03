-- =====================================================================
-- Jireta Loans & Credit Corp 1966
-- Migration : 00195_account_deletion.sql
-- Purpose   : Google Play-compliant account deletion.
--
--   * `deleted` account status (login is permanently blocked)
--   * `account_deletion_requests` queue for the PUBLIC Delete Account page
--     (https://www.jireta.com/delete-account) and for in-app requests
--   * `delete_user_account(uuid)` — one transaction that:
--       - refuses to delete an account with an outstanding loan
--         (`active` / `overdue`) or an in-flight disbursement
--       - cancels applications that never moved money
--       - removes profile / contact / KYC / device / OTP / MPIN data
--       - anonymizes `public.users`, `lender_profiles`, `rider_profiles`
--       - scrubs `auth.users` + deletes `auth.identities` / sessions / MFA
--         (the auth row must remain because loans reference it)
--       - KEEPS loan, payment, disbursement, collection and audit records
--         for the retention period required of a lending company
--
--   The Edge Function `account-delete` is the only caller and uses the
--   service role. No client can execute this function directly.
--
--   This migration changes NO existing rows. It only adds a lookup value,
--   one nullable column, one table, and one function.
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

-- ── 1. Account status ─────────────────────────────────────────────────
INSERT INTO public.user_account_statuses (code, label, sort_order)
VALUES ('deleted', 'Deleted', 5)
ON CONFLICT (code) DO NOTHING;

-- ── 2. Deletion metadata on the user row ──────────────────────────────
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS account_deleted_at TIMESTAMPTZ;

COMMENT ON COLUMN public.users.account_deleted_at IS
  'Kailan na-anonymize/na-delete ang account. NULL = active pa. Kapag may value, hindi na ito pwedeng mag-login.';

-- ── 3. Public deletion-request queue ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.account_deletion_requests (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reference        VARCHAR(32)  NOT NULL UNIQUE,
  user_id          UUID         REFERENCES public.users(id) ON DELETE SET NULL,
  role             TEXT,
  identifier       TEXT,
  identifier_type  TEXT         NOT NULL
                   CHECK (identifier_type IN ('phone', 'email')),
  -- SHA-256 ng `pepper:identifier` — para hindi mabasa ang numero/email
  -- kahit may makakuha ng table. Ginagamit sa duplicate-request check.
  identifier_hash  TEXT         NOT NULL,
  full_name        TEXT,
  reason           TEXT,
  source           TEXT         NOT NULL DEFAULT 'web'
                   CHECK (source IN ('web', 'in_app')),
  status           TEXT         NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'processing', 'completed', 'rejected')),
  ip_hash          TEXT,
  user_agent       TEXT,
  notes            TEXT,
  requested_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  processed_at     TIMESTAMPTZ,
  processed_by     UUID         REFERENCES public.users(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_account_deletion_requests_status
  ON public.account_deletion_requests(status, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_account_deletion_requests_hash
  ON public.account_deletion_requests(identifier_hash, requested_at DESC);

CREATE INDEX IF NOT EXISTS idx_account_deletion_requests_user
  ON public.account_deletion_requests(user_id, requested_at DESC);

DROP TRIGGER IF EXISTS trg_account_deletion_requests_updated_at
  ON public.account_deletion_requests;
CREATE TRIGGER trg_account_deletion_requests_updated_at
  BEFORE UPDATE ON public.account_deletion_requests
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE public.account_deletion_requests ENABLE ROW LEVEL SECURITY;

-- Wala itong anumang policy: tanging service_role (Edge Function) ang
-- makakabasa/makakasulat. Norma ng Supabase, may default grant sa bagong
-- tables, kaya tahasan itong binabawi.
REVOKE ALL ON TABLE public.account_deletion_requests FROM PUBLIC;
REVOKE ALL ON TABLE public.account_deletion_requests FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.account_deletion_requests
  TO service_role;

COMMENT ON TABLE public.account_deletion_requests IS
  'Pending/processed na account-deletion requests mula sa public /delete-account page at sa app. Service-role-only; walang RLS policy.';

-- ── 4. Deletion / anonymization function ──────────────────────────────
CREATE OR REPLACE FUNCTION public.delete_user_account(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
  v_account_status TEXT;
  v_role           TEXT;
  v_phone          TEXT;
  v_email          TEXT;
  v_e164           TEXT;
  v_new_email      TEXT;
  v_blocking       TEXT[];
  v_cancelled      INT := 0;
  v_now            TIMESTAMPTZ := NOW();
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'ACCOUNT_NOT_FOUND';
  END IF;

  SELECT u.account_status, u.phone_number, lower(COALESCE(u.email, '')), r.name
    INTO v_account_status, v_phone, v_email, v_role
  FROM public.users u
  JOIN public.roles r ON r.id = u.role_id
  WHERE u.id = p_user_id
  FOR UPDATE OF u;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ACCOUNT_NOT_FOUND';
  END IF;

  IF v_account_status = 'deleted' THEN
    RAISE EXCEPTION 'ALREADY_DELETED';
  END IF;

  IF v_role NOT IN ('lender', 'rider') THEN
    RAISE EXCEPTION 'ROLE_NOT_DELETABLE';
  END IF;

  -- ── Outstanding money: huwag payagan ───────────────────────────────
  IF v_role = 'lender' THEN
    SELECT array_agg(l.status::text ORDER BY l.status)
      INTO v_blocking
    FROM public.loans l
    WHERE l.lender_id = p_user_id
      AND l.status IN ('active', 'overdue');

    IF v_blocking IS NOT NULL THEN
      RAISE EXCEPTION 'OPEN_LOANS:%', array_to_string(v_blocking, ',');
    END IF;
  ELSE
    IF EXISTS (
      SELECT 1 FROM public.collection_assignments c
      WHERE c.rider_id = p_user_id
        AND c.status IN ('assigned', 'accepted', 'in_progress')
    ) THEN
      RAISE EXCEPTION 'OPEN_COLLECTIONS';
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.credit_investigations ci
      WHERE ci.rider_id = p_user_id
        AND ci.status IN ('assigned', 'accepted', 'in_progress')
    ) THEN
      RAISE EXCEPTION 'OPEN_CREDIT_INVESTIGATIONS';
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.disbursements d
      WHERE d.rider_id = p_user_id
        AND d.status IN ('pending', 'processing')
    ) THEN
      RAISE EXCEPTION 'OPEN_DISBURSEMENTS';
    END IF;
  END IF;

  -- Kahit `approved` o `under_review` pa lang, walang perang lumabas:
  -- kanselahin ang application bago i-anonymize ang account.
  UPDATE public.loans
  SET status = 'cancelled',
      updated_at = v_now
  WHERE lender_id = p_user_id
    AND status NOT IN ('completed', 'rejected', 'cancelled');
  GET DIAGNOSTICS v_cancelled = ROW_COUNT;

  v_e164 := CASE
    WHEN v_phone ~ '^09[0-9]{9}$' THEN '+63' || substr(v_phone, 2)
    ELSE NULL
  END;
  v_new_email := 'deleted+' || replace(p_user_id::text, '-', '') || '@deleted.invalid';

  -- ── 5. Delete directly identifying rows (idempotent, safe) ──────────
  BEGIN DELETE FROM public.addresses WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.emergency_contacts WHERE lender_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.loan_emergency_contacts
   WHERE loan_id IN (SELECT id FROM public.loans WHERE lender_id = p_user_id);
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.account_upgrade_documents WHERE lender_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.user_devices WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.notifications WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.sms_logs WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.user_mpins WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.active_sessions WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.login_lockouts WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.email_verifications WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.mpin_reset_authorizations WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.terms_consent_logs WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.password_history WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.email_reset_otps
   WHERE user_id = p_user_id OR (v_email <> '' AND lower(email) = v_email);
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.email_register_otps
   WHERE v_email <> '' AND lower(email) = v_email;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.email_otp_lockouts
   WHERE v_email <> '' AND lower(email) = v_email;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.email_register_lockouts
   WHERE v_email <> '' AND lower(email) = v_email;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.otp_codes
   WHERE phone_number IN (v_phone, v_e164);
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.otp_lockouts
   WHERE phone_number IN (v_phone, v_e164);
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  -- Rider-only live location data.
  BEGIN DELETE FROM public.rider_locations WHERE rider_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM public.rider_location_history WHERE rider_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  -- ── 6. Anonymize the profile rows (keep ids for financial records) ──
  BEGIN
    UPDATE public.lender_profiles
    SET gender = NULL,
        gender_id = NULL,
        civil_status = NULL,
        civil_status_id = NULL,
        date_of_birth = NULL,
        employment_type = NULL,
        employment_type_id = NULL,
        employer_name = NULL,
        monthly_income = NULL,
        gcash_number = NULL,
        account_upgrade_status = 'not_submitted',
        account_upgrade_status_id = NULL,
        account_upgrade_rejection_notes = NULL,
        source_of_funds = NULL,
        updated_at = v_now
    WHERE id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN
    -- Older schema (bago ang UUID lookup columns) — retry sa safe na set.
    BEGIN
      UPDATE public.lender_profiles
      SET gender = NULL,
          civil_status = NULL,
          date_of_birth = NULL,
          employment_type = NULL,
          employer_name = NULL,
          monthly_income = NULL,
          gcash_number = NULL,
          account_upgrade_status = 'not_submitted',
          account_upgrade_rejection_notes = NULL,
          source_of_funds = NULL,
          updated_at = v_now
      WHERE id = p_user_id;
    EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;
  END;

  BEGIN
    UPDATE public.rider_profiles
    SET plate_number = 'DELETED',
        vehicle_brand = NULL,
        drivers_license_number = 'DELETED',
        drivers_license_expiry = NULL,
        is_available = FALSE,
        updated_at = v_now
    WHERE id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN
    UPDATE public.rider_profiles SET address = NULL WHERE id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  -- ── 7. Anonymize the public user row ───────────────────────────────
  UPDATE public.users
  SET email = v_new_email,
      phone_number = NULL,
      first_name = 'Deleted',
      middle_name = NULL,
      last_name = 'Account',
      suffix = NULL,
      account_status = 'deleted',
      account_deleted_at = v_now,
      fcm_token = NULL,
      profile_photo_url = NULL,
      force_password_change = TRUE,
      last_login_at = NULL,
      email_verified_at = NULL,
      updated_at = v_now
  WHERE id = p_user_id;

  -- ── 8. Scrub the GoTrue identity ──────────────────────────────────
  -- The auth.users row MUST stay: deleting it cascades to public.users →
  -- lender_profiles → loans, which would destroy financial records.
  UPDATE auth.users
  SET email = v_new_email,
      phone = NULL,
      phone_confirmed_at = NULL,
      confirmation_token = NULL,
      recovery_token = NULL,
      email_change = NULL,
      email_change_token_new = NULL,
      email_change_token_current = NULL,
      phone_change = NULL,
      phone_change_token = NULL,
      reauthentication_token = NULL,
      raw_user_meta_data = '{}'::jsonb,
      raw_app_meta_data = '{}'::jsonb,
      encrypted_password = NULL,
      banned_until = 'infinity'::timestamptz,
      updated_at = v_now
  WHERE id = p_user_id;

  BEGIN
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'auth' AND table_name = 'users' AND column_name = 'deleted_at'
    ) THEN
      EXECUTE 'UPDATE auth.users SET deleted_at = NOW() WHERE id = $1' USING p_user_id;
    END IF;
  END;

  BEGIN DELETE FROM auth.identities WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM auth.sessions WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM auth.mfa_factors WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  BEGIN DELETE FROM auth.one_time_tokens WHERE user_id = p_user_id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN NULL; END;

  RETURN jsonb_build_object(
    'user_id', p_user_id,
    'role', v_role,
    'deleted_at', v_now,
    'anonymized_email', v_new_email,
    'cancelled_loans', v_cancelled,
    'phone_removed', v_phone IS NOT NULL,
    'email_removed', v_email <> '',
    'removed', jsonb_build_array(
      'addresses', 'emergency_contacts', 'account_upgrade_documents',
      'user_devices', 'notifications', 'sms_logs', 'user_mpins',
      'active_sessions', 'email_otps', 'sms_otps', 'rider_locations'
    ),
    'retained', jsonb_build_array(
      'loans', 'loan_schedules', 'payments', 'payment_reversals',
      'disbursements', 'collection_assignments', 'credit_investigations',
      'auth_logs', 'audit_logs'
    )
  );
END;
$$;

COMMENT ON FUNCTION public.delete_user_account(UUID) IS
  'Service-role-only na account deletion: block kapag may active/overdue loan o in-flight disbursement; i-cancel ang walang perang application; i-anonymize ang profile at auth identity; i-retain ang financial at audit records.';

REVOKE ALL ON FUNCTION public.delete_user_account(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_user_account(UUID) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_user_account(UUID) TO service_role;

COMMIT;
