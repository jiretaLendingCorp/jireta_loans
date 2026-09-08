-- =====================================================================
-- Jireta Loans & Credit Corp
-- Migration : 00139_seed_overdue_lender.sql
-- Purpose   : Create ONE lender test account whose weekly loan is OVERDUE
--             (30+ days past due, no payment) so the Head Manager /
--             Employee can inspect the overdue + 20% penalty result.
--
--   Login (mobile app, phone + password):
--     Phone    : 09171234567
--     Password : 12345678
--     Role     : lender
--
--   What it creates:
--     • auth.users  → password login (bcrypt-hashed)
--     • public.users + lender_profiles (account upgrade VERIFIED)
--     • addresses   (home, primary)
--     • loan        ₱5,000 weekly × 4 installments, status 'overdue'
--     • loan_schedules 4 weekly installments, all due 5+ weeks ago
--     • disbursements  office_cash released the day the loan started
--     • penalty_logs   20% of total payable (auto penalty, applied_by NULL)
--
--   Idempotent: phone 09171234567 is the unique key; re-running the
--   migration simply skips everything (ON CONFLICT DO NOTHING).
-- =====================================================================

BEGIN;

SET search_path = public, extensions;

DO $$
DECLARE
  v_user_id     UUID := 'd1a2b3c4-0000-4000-8000-0000000000a1';
  v_role_lender UUID;
  v_loan_id     UUID := 'd1a2b3c4-0000-4000-8000-0000000000a2';
  v_principal   NUMERIC := 5000.00;
  v_rate        NUMERIC := 20.00;
  v_total       NUMERIC;
  v_installment NUMERIC;
  v_created_at  TIMESTAMPTZ := now_manila() - INTERVAL '45 days';
BEGIN
  SELECT id INTO v_role_lender FROM public.roles WHERE name = 'lender';
  IF v_role_lender IS NULL THEN
    RAISE EXCEPTION 'lender role not found — run 00004_seed_data first';
  END IF;

  v_total := ROUND(v_principal * (1 + v_rate / 100), 2);        -- 6000.00
  v_installment := ROUND(v_total / 4, 2);                       -- 1500.00

  -- ── 1) auth.users (phone + password login) ─────────────────────────
  -- confirmed_at is a GENERATED column in modern GoTrue (computed from
  -- email_confirmed_at / phone_confirmed_at) — it cannot be inserted
  -- directly, so it is omitted here.
  INSERT INTO auth.users (
    instance_id, id, aud, role, email,
    encrypted_password, email_confirmed_at,
    recovery_token, email_change, email_change_token_new,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, phone, phone_confirmed_at,
    is_sso_user, deleted_at, is_anonymous
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    v_user_id,
    'authenticated',
    'authenticated',
    'overdue.lender@jireta.temp',
    crypt('12345678', gen_salt('bf')),   -- bcrypt $2a$ hash (GoTrue format)
    v_created_at,
    '', '', '',
    jsonb_build_object('provider', 'phone', 'providers', ARRAY['phone'], 'role', 'lender'),
    jsonb_build_object('first_name', 'Overdue', 'last_name', 'Lender'),
    v_created_at, v_created_at,
    '+639171234567',
    v_created_at,
    false, NULL, false
  )
  ON CONFLICT (id) DO NOTHING;

  -- ── 2) public.users + lender_profiles (verified) ────────────────────
  INSERT INTO public.users (
    id, role_id, phone_number, first_name, last_name,
    account_status, force_password_change, created_at, updated_at
  ) VALUES (
    v_user_id, v_role_lender, '09171234567', 'Overdue', 'Lender',
    'active', false, v_created_at, v_created_at
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.lender_profiles (
    id, gender, civil_status, date_of_birth,
    account_upgrade_status, created_at, updated_at
  ) VALUES (
    v_user_id, 'female', 'single', '1995-05-20',
    'verified', v_created_at, v_created_at
  )
  ON CONFLICT (id) DO NOTHING;

  -- ── 3) home address (primary) ───────────────────────────────────────
  INSERT INTO public.addresses (
    user_id, address_type, street, barangay, city, province, zip_code, is_primary
  ) VALUES (
    v_user_id, 'home', '123 Overdue St.', 'Barangay Test', 'Manila', 'Metro Manila', '1000', true
  )
  ON CONFLICT DO NOTHING;

  -- ── 4) loan — insert as 'pending', then walk the status flow guard ──
  --        (trigger blocks INSERT straight into approved/active/overdue)
  --        NOTE: set BOTH payment_frequency and payment_frequency_id — the
  --        sync trigger resolves the code from the id, and 00110 gave the id
  --        column a DEFAULT pointing at 'monthly', so omitting the id would
  --        silently rewrite 'weekly' to 'monthly'. Same for status_id.
  INSERT INTO public.loans (
    id, loan_number, lender_id, principal_amount, interest_rate,
    payment_frequency, payment_frequency_id, term_days, term_periods,
    installment_amount, purpose, status, status_id,
    approved_by, created_at, updated_at
  ) VALUES (
    v_loan_id, 'LN-OVD-0001', v_user_id, v_principal, v_rate,
    'weekly', (SELECT id FROM public.payment_frequencies WHERE code = 'weekly'),
    28, 4, v_installment,
    'Weekly loan that was never paid — overdue test account',
    'pending', (SELECT id FROM public.loan_statuses WHERE code = 'pending'),
    -- approved_by is required by loans_approved_requires_approver once the
    -- loan reaches approved/active/overdue — use the seed user as approver.
    v_user_id,
    v_created_at, v_created_at
  )
  ON CONFLICT (id) DO NOTHING;

  UPDATE public.loans SET status = 'approved'  WHERE id = v_loan_id AND status = 'pending';
  UPDATE public.loans SET status = 'active'    WHERE id = v_loan_id AND status = 'approved';
  UPDATE public.loans SET status = 'overdue'   WHERE id = v_loan_id AND status = 'active';

  -- ── 5) weekly schedules — due 5, 6, 7, 8 weeks ago (all unpaid) ─────
  INSERT INTO public.loan_schedules (loan_id, installment_number, due_date, amount_due, created_at, updated_at)
  SELECT
    v_loan_id,
    gs.n,
    (v_created_at + (gs.n || ' weeks')::interval)::date,
    v_installment,
    v_created_at,
    v_created_at
  FROM generate_series(1, 4) AS gs(n)
  ON CONFLICT (loan_id, installment_number) DO NOTHING;

  -- ── 6) disbursement — released the day the loan started ─────────────
  INSERT INTO public.disbursements (
    loan_id, authorized_by, method, amount, status, disbursed_at, created_at, updated_at
  ) VALUES (
    v_loan_id, v_user_id, 'office_cash', v_principal, 'completed', v_created_at, v_created_at, v_created_at
  )
  ON CONFLICT DO NOTHING;

  -- ── 7) automatic 20% penalty on total payable (6000 × 0.20 = 1200) ──
  INSERT INTO public.penalty_logs (
    loan_id, applied_by, penalty_basis, penalty_rate, penalty_amount, reason, applied_at
  ) VALUES (
    v_loan_id, NULL, v_total, 20.00, ROUND(v_total * 0.20, 2),
    'Automatic 20% penalty applied — loan overdue by 30+ days',
    v_created_at + INTERVAL '30 days'
  )
  ON CONFLICT DO NOTHING;

END $$;

COMMIT;