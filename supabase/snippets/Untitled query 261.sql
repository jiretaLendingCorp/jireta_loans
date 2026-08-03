-- =====================================================
-- CREATE NEW LOCAL ACCOUNT
-- Email: demohead@jiretaloans.com
-- Password: Demo1234!
-- =====================================================

-- Make sure pgcrypto exists
create extension if not exists pgcrypto;

-- Make sure role exists
insert into public.roles (name, description)
values ('head_manager', 'Full access')
on conflict (name) do nothing;

-- Create auth user manually
with new_user as (
  insert into auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    recovery_sent_at,
    last_sign_in_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  )
  values (
    gen_random_uuid(),
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'demohead@jiretaloans.com',
    crypt('Demo1234!', gen_salt('bf')),
    now(),
    now(),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now(),
    '',
    '',
    '',
    ''
  )
  returning id, email
)

-- Create public profile
insert into public.users (
  id,
  email,
  first_name,
  last_name,
  role_id,
  account_status,
  force_password_change,
  created_at
)
select
  u.id,
  u.email,
  'Demo',
  'Head',
  r.id,
  'active',
  false,
  now()
from new_user u
join public.roles r on r.name = 'head_manager';

-- Verify
select id, email
from auth.users
where email = 'demohead@jiretaloans.com';