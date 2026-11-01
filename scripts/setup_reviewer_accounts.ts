// scripts/setup_reviewer_accounts.ts
// ─────────────────────────────────────────────────────────────────────────────
// One-time (idempotent) setup para sa Google Play Store REVIEWER test accounts.
//
// Ginagawa nito para sa lender at rider:
//   1. Supabase Auth user (`auth.users`) na may:
//        • PH mobile phone (E.164) + `${phone}@jireta.temp` email
//        • password mula sa env (HINDI naka-commit sa repo)
//        • `app_metadata.reviewer = true`, `reviewer_role = lender|rider`
//          (service-role lang ang makakapagsulat nito — second allowlist layer)
//   2. `public.users` row na active, wastong role, at pangalan
//   3. `lender_profiles` / `rider_profiles` row
//   4. `user_mpins` row — para preserved ang MPIN login pagkatapos ng
//      reviewer sign-in (kapareho ng normal na OTP + MPIN flow)
//
// GAMIT (dry-run muna — walang sinusulat):
//   SUPABASE_URL="https://<ref>.supabase.co" \
//   SUPABASE_SERVICE_ROLE_KEY="<service-role-key>" \
//   REVIEWER_LENDER_PHONE="09000000101" \
//   REVIEWER_LENDER_PASSWORD="<16+ chars>" \
//   REVIEWER_RIDER_PHONE="09000000102" \
//   REVIEWER_RIDER_PASSWORD="<16+ chars>" \
//   REVIEWER_MPIN="2468" \
//   deno run --allow-net --allow-env scripts/setup_reviewer_accounts.ts
//
// Isulat talaga:
//   ... deno run --allow-net --allow-env scripts/setup_reviewer_accounts.ts --apply
//
// Idempotent: safe i-rerun — ina-update ang existing auth user/password,
// profiles, at MPIN; hindi gumagawa ng duplicate.
// ─────────────────────────────────────────────────────────────────────────────
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.95.0';
import { hashMpin } from '../supabase/functions/_shared/password_hash.ts';
import {
  normalizePhMobile,
  phoneToE164,
} from '../supabase/functions/_shared/validators.ts';

const APPLY = Deno.args.includes('--apply');

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')?.trim() ?? '';
const SERVICE_ROLE_KEY =
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim() ?? '';

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error(
    'Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY environment variables.',
  );
  Deno.exit(1);
}

const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const MPIN = (Deno.env.get('REVIEWER_MPIN') ?? '2468').trim();
if (!/^\d{4}$/.test(MPIN)) {
  console.error('REVIEWER_MPIN must be exactly 4 digits.');
  Deno.exit(1);
}

type ReviewerRole = 'lender' | 'rider';

interface ReviewerSetup {
  role: ReviewerRole;
  phone: string;
  e164: string;
  password: string;
  tempEmail: string;
  firstName: string;
  lastName: string;
}

function accountFromEnv(role: ReviewerRole): ReviewerSetup {
  const prefix = `REVIEWER_${role.toUpperCase()}`;
  const phone = normalizePhMobile(Deno.env.get(`${prefix}_PHONE`) ?? '');
  const password = (Deno.env.get(`${prefix}_PASSWORD`) ?? '').trim();
  const label = (Deno.env.get(`${prefix}_NAME`) ?? '').trim();

  if (!phone) {
    throw new Error(
      `${prefix}_PHONE is missing or not a valid PH mobile number (09XXXXXXXXX).`,
    );
  }
  if (password.length < 12) {
    throw new Error(
      `${prefix}_PASSWORD must be at least 12 characters (use 16+ random characters).`,
    );
  }

  const nameParts = label.split(/\s+/).filter(Boolean);
  return {
    role,
    phone,
    e164: phoneToE164(phone),
    password,
    tempEmail: `${phone}@jireta.temp`,
    firstName: nameParts[0] ?? 'Google Play',
    lastName: nameParts.slice(1).join(' ') || 'Reviewer',
  };
}

async function findAuthUser(e164: string, tempEmail: string) {
  const perPage = 1000;
  for (let page = 1; ; page++) {
    const { data, error } = await db.auth.admin.listUsers({ page, perPage });
    if (error) throw new Error(`listUsers failed: ${error.message}`);
    const users = data?.users ?? [];
    const found = users.find((u) =>
      u.phone === e164 || (u.email ?? '').toLowerCase() === tempEmail
    );
    if (found) return found;
    if (users.length < perPage) return null;
  }
}

async function roleIdFor(role: ReviewerRole): Promise<string> {
  const { data, error } = await db
    .from('roles')
    .select('id')
    .eq('name', role)
    .single();
  if (error || !data) {
    throw new Error(`Role '${role}' not found: ${error?.message ?? 'missing'}`);
  }
  return data.id as string;
}

async function provision(account: ReviewerSetup): Promise<void> {
  const roleId = await roleIdFor(account.role);
  const existing = await findAuthUser(account.e164, account.tempEmail);

  console.log(
    `\n[${account.role}] ${account.phone} — ${
      existing ? `update auth user ${existing.id}` : 'create auth user'
    }`,
  );

  if (!APPLY) {
    console.log('  (dry-run) auth user, public.users, profile, MPIN');
    return;
  }

  const displayName = `${account.firstName} ${account.lastName}`.trim();
  const appMetadata = {
    ...(existing?.app_metadata ?? {}),
    role: account.role,
    reviewer: true,
    reviewer_role: account.role,
  };
  const userMetadata = {
    ...(existing?.user_metadata ?? {}),
    display_name: displayName,
    name: displayName,
    full_name: displayName,
    first_name: account.firstName,
    last_name: account.lastName,
    phone: account.phone,
  };

  let authUserId = existing?.id ?? '';
  if (existing) {
    const { data, error } = await db.auth.admin.updateUserById(existing.id, {
      phone: account.e164,
      email: account.tempEmail,
      password: account.password,
      phone_confirm: true,
      email_confirm: true,
      app_metadata: appMetadata,
      user_metadata: userMetadata,
    });
    if (error || !data?.user) {
      throw new Error(`updateUserById failed: ${error?.message ?? 'no user'}`);
    }
    authUserId = data.user.id;
  } else {
    const { data, error } = await db.auth.admin.createUser({
      phone: account.e164,
      email: account.tempEmail,
      password: account.password,
      phone_confirm: true,
      email_confirm: true,
      app_metadata: appMetadata,
      user_metadata: userMetadata,
    });
    if (error || !data?.user) {
      throw new Error(`createUser failed: ${error?.message ?? 'no user'}`);
    }
    authUserId = data.user.id;
  }

  // public.users — the auth sync trigger may have created a stub row; this
  // upsert makes the role/name/status authoritative.
  const { error: userErr } = await db.from('users').upsert({
    id: authUserId,
    role_id: roleId,
    phone_number: account.phone,
    // Mobile lenders/riders keep public.users.email NULL — the @jireta.temp
    // address is an internal GoTrue credential only.
    email: null,
    first_name: account.firstName,
    last_name: account.lastName,
    account_status: 'active',
    force_password_change: false,
  }, { onConflict: 'id' });
  if (userErr) throw new Error(`users upsert failed: ${userErr.message}`);

  if (account.role === 'lender') {
    const { error } = await db.from('lender_profiles').upsert({
      id: authUserId,
      account_upgrade_status: 'not_submitted',
    }, { onConflict: 'id' });
    if (error) throw new Error(`lender_profiles upsert failed: ${error.message}`);
  } else {
    const { error } = await db.from('rider_profiles').upsert({
      id: authUserId,
      plate_number: 'REV-0001',
      vehicle_type: 'Motorcycle',
      drivers_license_number: 'REV-DL-0001',
      is_available: true,
    }, { onConflict: 'id' });
    if (error) throw new Error(`rider_profiles upsert failed: ${error.message}`);
  }

  const mpinHash = await hashMpin(authUserId, MPIN);
  const { error: mpinErr } = await db.from('user_mpins').upsert({
    user_id: authUserId,
    mpin_hash: mpinHash,
    failed_attempts: 0,
    locked_until: null,
    change_window_start: new Date().toISOString(),
    change_count: 0,
  }, { onConflict: 'user_id' });
  if (mpinErr) throw new Error(`user_mpins upsert failed: ${mpinErr.message}`);

  // Clean slate para sa reviewer: walang lumang session/OTP lockout.
  await db.from('active_sessions').delete().eq('user_id', authUserId);
  await db.from('otp_codes').delete().eq('phone_number', account.phone);
  await db.from('otp_lockouts').delete().eq('phone_number', account.phone);

  console.log(`  ✓ provisioned (user_id=${authUserId}, MPIN set)`);
}

async function main() {
  const accounts = [
    accountFromEnv('lender'),
    accountFromEnv('rider'),
  ];

  if (accounts[0].phone === accounts[1].phone) {
    throw new Error('Lender and rider reviewer phones must be different.');
  }

  console.log(
    APPLY
      ? 'APPLY mode — writing reviewer accounts.'
      : 'DRY-RUN — no writes. Re-run with --apply to write.',
  );

  for (const account of accounts) await provision(account);

  console.log('\n── Google Play Console → App access ─────────────────────');
  for (const account of accounts) {
    console.log(
      `${account.role.toUpperCase()}: phone ${account.phone} | password ${account.password} | MPIN ${MPIN}`,
    );
  }
  console.log('\nKeep these values in Supabase secrets + Play Console only.');
  console.log('Required Edge Function secrets:');
  console.log(`  REVIEWER_LOGIN_ENABLED=true`);
  console.log(`  REVIEWER_LENDER_PHONE=${accounts[0].phone}`);
  console.log(`  REVIEWER_LENDER_PASSWORD=${accounts[0].password}`);
  console.log(`  REVIEWER_RIDER_PHONE=${accounts[1].phone}`);
  console.log(`  REVIEWER_RIDER_PASSWORD=${accounts[1].password}`);
}

try {
  await main();
} catch (err) {
  console.error('\nSetup failed:', (err as Error)?.message ?? err);
  Deno.exit(1);
}
