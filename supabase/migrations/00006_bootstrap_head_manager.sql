-- ═══════════════════════════════════════════════════════════════════════════
-- Jireta Loans & Credit Corp 1966
-- Migration : 00006_bootstrap_head_manager.sql
-- Purpose   : Seeds the very first head_manager account.
--
-- WHY THIS EXISTS
-- ─────────────────────────────────────────────────────────────────────────
-- auth-login queries public.users BEFORE calling signInWithPassword().
-- Users created via the Supabase Dashboard (Auth → Add User) only exist in
-- auth.users — they are invisible to the Edge Function → instant 401.
-- All users MUST be created through the proper Edge Functions (which write
-- to both auth.users and public.users atomically). But those functions
-- require an authenticated head_manager — chicken-and-egg for the very
-- first account.
-- This script breaks that deadlock by directly inserting the first
-- head_manager into both tables inside a single transaction.
--
-- HOW TO RUN
-- ─────────────────────────────────────────────────────────────────────────
-- 1. Open: Supabase Dashboard → SQL Editor
-- 2. Replace the three CHANGE_ME placeholders below with real values.
-- 3. Run the script. Check the NOTICE at the end for success.
-- 4. Log in through the app. You will be forced to change your password.
--
-- IDEMPOTENT — safe to re-run; skips if the email already exists.
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  -- ── CHANGE THESE THREE VALUES ─────────────────────────────────────────
  v_email      TEXT    := 'admin@jireta.com';   -- head manager email
  v_password   TEXT    := 'Admin@12345';         -- temporary password (user will be forced to change it)
  v_first_name TEXT    := 'Admin';
  v_last_name  TEXT    := 'Manager';
  -- ─────────────────────────────────────────────────────────────────────

  v_user_id    UUID;
  v_role_id    UUID;
  v_exists     BOOLEAN;
BEGIN

  -- ── Guard: already exists in auth.users? ────────────────────────────────
  SELECT EXISTS(SELECT 1 FROM auth.users WHERE email = lower(v_email))
  INTO v_exists;

  IF v_exists THEN
    RAISE NOTICE
      '[bootstrap] auth.users already has %. Checking public.users...',
      v_email;

    SELECT id INTO v_user_id FROM auth.users WHERE email = lower(v_email);

    IF EXISTS(SELECT 1 FROM public.users WHERE id = v_user_id) THEN
      RAISE NOTICE '[bootstrap] public.users row also exists. Nothing to do.';
      RETURN;
    END IF;

    -- auth.users exists but public.users row is missing — insert it now.
    RAISE NOTICE '[bootstrap] public.users row is MISSING. Inserting...';
  ELSE
    -- ── Create auth.users row ─────────────────────────────────────────────
    -- We use gen_random_uuid() so the UUID is Supabase-native.
    v_user_id := gen_random_uuid();

    INSERT INTO auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at,
      confirmation_token,
      email_change,
      email_change_token_new,
      recovery_token
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      v_user_id,
      'authenticated',
      'authenticated',
      lower(v_email),
      crypt(v_password, gen_salt('bf')),  -- bcrypt hash
      NOW(),                              -- email_confirmed_at → pre-confirm
      '{"provider":"email","providers":["email"]}',
      '{}',
      NOW(),
      NOW(),
      '', '', '', ''
    );

    RAISE NOTICE '[bootstrap] auth.users row created with id=%', v_user_id;
  END IF;

  -- ── Resolve head_manager role id ─────────────────────────────────────────
  SELECT id INTO v_role_id
  FROM   public.roles
  WHERE  name = 'head_manager';

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION
      '[bootstrap] Role "head_manager" not found in public.roles. '
      'Have you run migration 00004_seed_data.sql?';
  END IF;

  -- ── Insert public.users row ──────────────────────────────────────────────
  INSERT INTO public.users (
    id,
    role_id,
    email,
    first_name,
    last_name,
    account_status,
    force_password_change,
    created_at,
    updated_at
  ) VALUES (
    v_user_id,
    v_role_id,
    lower(v_email),
    v_first_name,
    v_last_name,
    'active',
    TRUE,    -- forces a password change on first login (recommended)
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;  -- idempotent

  RAISE NOTICE
    '[bootstrap] SUCCESS. Head manager created: email=%, id=%',
    v_email, v_user_id;
  RAISE NOTICE
    '[bootstrap] Default password: %. User will be prompted to change it on first login.',
    v_password;

END;
$$;
