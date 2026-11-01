// scripts/check_reviewer_accounts.ts
// ─────────────────────────────────────────────────────────────────────────────
// READ-ONLY diagnostics para sa Google Play reviewer accounts.
//
// Sinusuri nito ang LAHAT ng kailangan ng `auth-reviewer?fn=login` at sinasabi
// kung aling check ang bumagsak — walang binabago sa database maliban sa isang
// panandaliang GoTrue sign-in (agad ding nag-sign-out) para ma-test ang
// password. HINDI nito ipinapakita ang password, ang haba lang.
//
// GAMIT:
//   SUPABASE_URL="https://<ref>.supabase.co" \
//   SUPABASE_SERVICE_ROLE_KEY="<service-role-key>" \
//   SUPABASE_ANON_KEY="<anon-key>" \
//   REVIEWER_LENDER_PHONE="09000000101" \
//   REVIEWER_LENDER_PASSWORD="<lender password>" \
//   REVIEWER_RIDER_PHONE="09000000102" \
//   REVIEWER_RIDER_PASSWORD="<rider password>" \
//   deno run --allow-net --allow-env scripts/check_reviewer_accounts.ts
//
// Exit code 1 kapag may failed check — safe gamitin sa deploy/checklist.
// ─────────────────────────────────────────────────────────────────────────────
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.95.0';
import {
  normalizePhMobile,
  phoneToE164,
} from '../supabase/functions/_shared/validators.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')?.trim() ?? '';
const SERVICE_ROLE_KEY =
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim() ?? '';
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')?.trim() ?? '';

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error(
    'Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY environment variables.',
  );
  Deno.exit(1);
}

const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

type ReviewerRole = 'lender' | 'rider';

interface Account {
  role: ReviewerRole;
  phone: string;
  e164: string;
  password: string;
}

function accountFromEnv(role: ReviewerRole): Account | null {
  const prefix = `REVIEWER_${role.toUpperCase()}`;
  const phone = normalizePhMobile(Deno.env.get(`${prefix}_PHONE`) ?? '');
  const password = (Deno.env.get(`${prefix}_PASSWORD`) ?? '').trim();
  if (!phone || password.length < 12) return null;
  return { role, phone, e164: phoneToE164(phone), password };
}

function mark(ok: boolean): string {
  return ok ? 'OK' : 'FAIL';
}

async function check(account: Account): Promise<boolean> {
  console.log(`\n[${account.role}] ${account.phone}`);
  let ok = true;
  const fail = (message: string) => {
    ok = false;
    console.log(`  ${message}`);
  };

  console.log(`  config: password length ${account.password.length} (masked)`);

  const { data: userRow, error: userErr } = await db
    .from('users')
    .select('id, account_status, phone_number, roles!users_role_id_fkey(name)')
    .eq('phone_number', account.phone)
    .maybeSingle();

  if (userErr) {
    fail(`public.users: FAIL (query error: ${userErr.message})`);
    return false;
  }
  if (!userRow) {
    fail(
      'public.users: FAIL (not found) → run scripts/setup_reviewer_accounts.ts --apply against THIS project',
    );
    return false;
  }

  const roleName = (userRow.roles as { name?: string } | null)?.name ?? '';
  console.log(
    `  public.users: ${mark(roleName === account.role && userRow.account_status === 'active')} (role=${roleName || 'none'}, status=${userRow.account_status})`,
  );
  if (roleName !== account.role || userRow.account_status !== 'active') {
    ok = false;
  }

  const { data: authData, error: authErr } = await db.auth.admin.getUserById(
    userRow.id as string,
  );
  const authUser = authData?.user;
  if (authErr || !authUser) {
    fail(`auth user: FAIL (${authErr?.message ?? 'not found'})`);
    return false;
  }

  const meta = (authUser.app_metadata ?? {}) as Record<string, unknown>;
  const authPhone = normalizePhMobile(authUser.phone ?? '');
  const tempEmail = `${account.phone}@jireta.temp`;
  const authEmailMatches =
    (authUser.email ?? '').trim().toLowerCase() === tempEmail;
  const identityOk = authPhone === account.phone || authEmailMatches;
  const authOk = meta['reviewer'] === true &&
    meta['reviewer_role'] === account.role &&
    identityOk;
  console.log(
    `  auth user: ${mark(authOk)} (phone=${authUser.phone ?? 'null'}, normalized=${authPhone || 'none'}, email=${authUser.email ?? 'null'}, email_matches=${authEmailMatches}, reviewer=${String(meta['reviewer'])}, reviewer_role=${String(meta['reviewer_role'])})`,
  );
  if (!authOk) ok = false;

  const profileTable = account.role === 'lender'
    ? 'lender_profiles'
    : 'rider_profiles';
  const { data: profileRow } = await db
    .from(profileTable)
    .select('id')
    .eq('id', userRow.id as string)
    .maybeSingle();
  console.log(`  ${profileTable}: ${mark(profileRow != null)}`);
  if (!profileRow) ok = false;

  const { data: mpinRow } = await db
    .from('user_mpins')
    .select('user_id')
    .eq('user_id', userRow.id as string)
    .maybeSingle();
  console.log(`  user_mpins (MPIN set): ${mark(mpinRow != null)}`);
  if (!mpinRow) ok = false;

  if (!ANON_KEY) {
    console.log('  live sign-in: SKIP (SUPABASE_ANON_KEY not set)');
    return ok;
  }

  const anon = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  let signedIn = false;
  try {
    const { data, error } = await anon.auth.signInWithPassword({
      phone: account.e164,
      password: account.password,
    });
    signedIn = !!data?.session && !error;
    if (!signedIn) {
      console.log(`  live sign-in: FAIL (${error?.message ?? 'no session'})`);
      console.log(
        '    → the password in the secret does not match the GoTrue credential; re-run setup with --apply',
      );
    } else {
      console.log('  live sign-in: OK');
    }
  } catch (e) {
    console.log(`  live sign-in: FAIL (${(e as Error)?.message ?? e})`);
  } finally {
    if (signedIn) await anon.auth.signOut().catch(() => {});
  }
  if (!signedIn) ok = false;

  return ok;
}

async function main() {
  let allOk = true;
  for (const role of ['lender', 'rider'] as const) {
    const account = accountFromEnv(role);
    if (!account) {
      const prefix = `REVIEWER_${role.toUpperCase()}`;
      console.log(
        `\n[${role}] NOT CONFIGURED — set ${prefix}_PHONE and ${prefix}_PASSWORD (password 12+ chars).`,
      );
      allOk = false;
      continue;
    }
    if (!(await check(account))) allOk = false;
  }

  console.log(
    allOk
      ? '\nAll reviewer checks passed.'
      : '\nSome checks failed — see the FAIL lines above.',
  );
  if (!allOk) Deno.exit(1);
}

await main();
