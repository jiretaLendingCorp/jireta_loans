// scripts/fix_auth_emails.ts
// ─────────────────────────────────────────────────────────────────────────────
// Isahang-takbo na repair script para sa **desynced na `auth.users`**.
//
// Problema: ang self-registered lender ay may sintetikong
// `${phone}@jireta.temp` na credential sa Supabase Auth. Noong na-verify niya
// ang totoong email sa app, `public.users.email` lang ang naisusulat (ang
// confirm handler ay hindi nag-sync sa GoTrue) — kaya sa
// Authentication → Users ay TEMP pa rin ang email at `-` ang Display name
// kahit tama na ang email sa app. Naka-ayos na ang forward path
// (`auth-email-verify?fn=confirm` at `users-manage` PATCH ay pareho nang
// nag-sync), pero ang mga DATI nang naka-record ay kailangan ng isahang ayos —
// ito iyon.
//
// GAMIT (dry-run muna — walang sinusulat; i-review ang listahan):
//   SUPABASE_URL="https://<ref>.supabase.co" \
//   SUPABASE_SERVICE_ROLE_KEY="<service-role-key>" \
//   deno run --allow-net --allow-env scripts/fix_auth_emails.ts
//
// Isulat talaga (mangailangan ng `--apply`; SERVICE ROLE key = full access —
// huwag i-commit, huwag i-paste sa chat):
//   ... deno run --allow-net --allow-env scripts/fix_auth_emails.ts --apply
//
// Idempotent ito: ang mga email na pantay na (case-insensitive) ay nilalaktawan,
// at ang email ay hindi ginagalaw kapag may IBANG auth user nang gumagamit nito.
// ─────────────────────────────────────────────────────────────────────────────
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.95.0';

const APPLY = Deno.args.includes('--apply');

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')?.trim() ?? '';
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim() ?? '';

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error(
    'Kailangan ang SUPABASE_URL at SUPABASE_SERVICE_ROLE_KEY environment variables.',
  );
  Deno.exit(1);
}

const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const TEMP_EMAIL_SUFFIX = '@jireta.temp';

interface PublicUser {
  id: string;
  email: string | null;
  first_name: string | null;
  last_name: string | null;
  phone_number: string | null;
}

function displayMetadata(u: PublicUser): Record<string, string> {
  const first = (u.first_name ?? '').trim();
  const last = (u.last_name ?? '').trim();
  const phone = (u.phone_number ?? '').trim();
  const fullName = [first, last].filter(Boolean).join(' ');
  const meta: Record<string, string> = {};
  if (fullName) {
    meta.display_name = fullName;
    meta.name = fullName;
    meta.full_name = fullName;
  }
  if (first) meta.first_name = first;
  if (last) meta.last_name = last;
  if (phone) meta.phone = phone;
  return meta;
}

async function loadPublicUsers(): Promise<Map<string, PublicUser>> {
  const byId = new Map<string, PublicUser>();
  const pageSize = 1000;
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await db
      .from('users')
      .select('id, email, first_name, last_name, phone_number')
      .range(from, from + pageSize - 1);
    if (error) throw new Error(`users select failed: ${error.message}`);
    for (const row of (data ?? []) as PublicUser[]) byId.set(row.id, row);
    if (!data || data.length < pageSize) break;
  }
  return byId;
}

const publicUsers = await loadPublicUsers();
console.log(`public.users: ${publicUsers.size} rows`);
console.log(APPLY ? 'Mode: APPLY (isusulat ang mga pagbabago)' : 'Mode: DRY-RUN (walang isusulat)');

let scanned = 0;
let emailFixes = 0;
let metaFixes = 0;
let duplicates = 0;
let failures = 0;

for (let page = 1; ; page += 1) {
  const { data, error } = await db.auth.admin.listUsers({ page, perPage: 200 });
  if (error) {
    console.error('listUsers failed:', error.message);
    Deno.exit(1);
  }
  const authUsers = data?.users ?? [];
  if (authUsers.length === 0) break;

  for (const authUser of authUsers) {
    scanned += 1;
    const publicUser = publicUsers.get(authUser.id);
    if (!publicUser) continue;

    const wantedEmail = (publicUser.email ?? '').trim().toLowerCase();
    if (!wantedEmail || wantedEmail.endsWith(TEMP_EMAIL_SUFFIX)) continue; // phone-only lender

    const currentEmail = (authUser.email ?? '').trim().toLowerCase();
    const currentMeta = (authUser.user_metadata ?? {}) as Record<string, unknown>;
    const wantedMeta = displayMetadata(publicUser);

    const emailChanged = currentEmail !== wantedEmail;
    const metaChanged = Object.entries(wantedMeta).some(
      ([k, v]) => String(currentMeta[k] ?? '') !== v,
    );
    if (!emailChanged && !metaChanged) continue;

    const label = `${authUser.id} ${currentEmail || '(blank)'} -> ${wantedEmail}`;
    console.log(`• ${label}${metaChanged ? ' [+metadata]' : ''}`);

    if (emailChanged) emailFixes += 1;
    if (metaChanged) metaFixes += 1;

    if (!APPLY) continue;

    const update: {
      email?: string;
      email_confirm?: boolean;
      user_metadata?: Record<string, unknown>;
    } = {};
    if (emailChanged) {
      update.email = wantedEmail;
      update.email_confirm = true;
    }
    if (metaChanged) update.user_metadata = { ...currentMeta, ...wantedMeta };

    const { error: updErr } = await db.auth.admin.updateUserById(authUser.id, update);
    if (updErr) {
      const msg = (updErr.message ?? '').toLowerCase();
      const isDuplicate = msg.includes('already') || msg.includes('duplicate') ||
        msg.includes('exists') || msg.includes('registered');
      if (isDuplicate) {
        duplicates += 1;
        console.warn(`  ! duplicate sa GoTrue — nilaktawan: ${updErr.message}`);
      } else {
        failures += 1;
        console.error(`  ! bigo: ${updErr.message}`);
      }
      continue;
    }
    console.log('  ✓ naisulat');
  }

  if (authUsers.length < 200) break;
}

console.log('');
console.log('── Buod ─────────────────────────────');
console.log(`auth users na na-scan : ${scanned}`);
console.log(`email na kailangang i-sync : ${emailFixes}`);
console.log(`display metadata : ${metaFixes}`);
if (APPLY) {
  console.log(`duplicate (nilaktawan) : ${duplicates}`);
  console.log(`bigo : ${failures}`);
  if (failures > 0 || duplicates > 0) Deno.exit(2);
} else if (emailFixes > 0 || metaFixes > 0) {
  console.log('');
  console.log('Dry-run lang ito. Patakbuhin ulit na may `--apply` para isulat.');
}
