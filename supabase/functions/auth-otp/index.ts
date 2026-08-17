// supabase/functions/auth-otp/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   auth-send-otp    →  ?fn=send-otp
//   auth-verify-otp  →  ?fn=verify-otp
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePhone, sanitizeString } from '../_shared/validators.ts';
import { sendSms } from '../_shared/sms.ts';
import { singleWithObjectEmbeds, type DbClient } from '../_shared/types.ts';
import { guardRateLimit, recordSecurityEvent, blockKey, checkBlock } from '../_shared/rate_limiter.ts';

// ── [moved from auth-send-otp] ──────────────────────────────────────────────
const OTP_RATE_LIMIT = 10;
const OTP_WINDOW_MINUTES = 10;
const OTP_EXPIRY_MINUTES = 10;

// Abuse detection: 10 OTP requests per phone per 10 minutes (the stored
// otp_codes count above) PLUS an IP-scoped guard so one IP cannot spray OTP
// across many phone numbers (phone-number enumeration / SMS bombing).
const OTP_IP_RATE_MAX = 20;
const OTP_IP_WINDOW_MINUTES = 10;
const OTP_BLOCK_MINUTES = 15;

function clientIp(req: Request): string {
  return req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown';
}

// ── [moved from auth-verify-otp] ────────────────────────────────────────────
const MAX_OTP_ATTEMPTS = 5;
const DEFAULT_PASSWORD = '12345678';
const OTP_PASSWORD = (phone: string) => `OTP_${phone}_SECURE`;

// ── [moved from auth-verify-otp] ────────────────────────────────────────────
function toE164(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  if (digits.startsWith('63')) return `+${digits}`;
  if (digits.startsWith('0')) return `+63${digits.slice(1)}`;
  return `+63${digits}`;
}

// ── [moved from auth-verify-otp] ────────────────────────────────────────────
async function selfRegisterLender(db: DbClient, phone: string) {
  const { data: roleData } = await db.from('roles').select('id').eq('name', 'lender').single();
  if (!roleData) return null;

  // Lenders are identified by PHONE only — public.users.email stays NULL and
  // no synthetic email is ever shown to the app. The temp email below is an
  // internal GoTrue credential only (some installs, e.g. local dev, reject
  // phone+password sign-in unless SMS auth is provisioned).
  const { data: authUser, error: authErr } = await db.auth.admin.createUser({
    phone: toE164(phone),
    email: `${phone}@jireta.temp`,
    password: OTP_PASSWORD(phone),
    phone_confirm: true,
    email_confirm: true,
    app_metadata: { role: 'lender' },
  });
  if (authErr || !authUser?.user) return null;

  const { data: newUser, error: userErr } = await db.from('users').upsert({
    id: authUser.user.id,
    role_id: roleData.id,
    phone_number: phone,
    email: null,
    // No placeholder name — the real identity is captured later via
    // Account Upgrade / profile edit, not auto-filled here.
    first_name: '',
    last_name: '',
    account_status: 'active',
    force_password_change: false,
    created_by: null,
  }, { onConflict: 'id' }).select('id, account_status, email, first_name, last_name, phone_number, force_password_change, roles(name)').single();

  if (userErr || !newUser) {
    await db.auth.admin.deleteUser(authUser.user.id).catch(() => {});
    return null;
  }

  const { error: profileErr } = await db.from('lender_profiles').insert({
    id: newUser.id,
    account_upgrade_status: 'not_submitted',
  });
  if (profileErr) {
    await db.auth.admin.deleteUser(authUser.user.id).catch(() => {});
    await Promise.resolve(db.from('users').delete().eq('id', newUser.id)).catch(() => {});
    return null;
  }

  return singleWithObjectEmbeds(newUser);
}

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'send-otp';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'send-otp':
        // ── [moved from functions/auth-send-otp/index.ts] ───────────────
        return await handleSendOtp(req);
      case 'verify-otp':
        // ── [moved from functions/auth-verify-otp/index.ts] ─────────────
        return await handleVerifyOtp(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('auth-otp error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/auth-send-otp/index.ts] ───────────────────────────
async function handleSendOtp(req: Request) {
  const { phone_number } = await req.json();
  const phone = sanitizeString(String(phone_number ?? ''));
  const ip = clientIp(req);

  if (!validatePhone(phone)) return errorResponse('Invalid Philippine phone number (09XXXXXXXXX)', 400, 'VALIDATION_ERROR');

  const db = getAdminClient();

  // Abuse detection (IP-scoped): 20 OTP sends per IP per 10 minutes → block.
  // Checked first so a flood cannot reach the DB / SMS provider.
  const ipGuard = await guardRateLimit({
    key: `otp:ip:${ip}`,
    maxAttempts: OTP_IP_RATE_MAX,
    windowMinutes: OTP_IP_WINDOW_MINUTES,
    blockMinutes: OTP_BLOCK_MINUTES,
    blockReason: 'Too many OTP requests from this device/IP',
    eventType: 'otp_rate_limited',
    ipAddress: ip,
  });
  if (!ipGuard.allowed) {
    return errorResponse(
      'Too many OTP requests from this device. Try again in 15 minutes.',
      429,
      'OTP_RATE_LIMITED',
    );
  }

  // Lenders may self-register via OTP: an unregistered phone is allowed to
  // request an OTP. Riders must be registered by the head manager first, so
  // once a phone IS registered we only allow OTP for rider/lender roles.
  const { data: userRow } = await db
    .from('users')
    .select('id, account_status, roles(name)')
    .eq('phone_number', phone)
    .maybeSingle();
  const user = singleWithObjectEmbeds(userRow);

  let userId: string | null = null;
  if (user) {
    if (user.account_status === 'archived') return errorResponse('Account archived', 403, 'ACCOUNT_ARCHIVED');
    if (user.account_status === 'inactive') return errorResponse('Account inactive', 403, 'ACCOUNT_INACTIVE');

    const role = user?.roles?.name;
    if (!['rider', 'lender'].includes(role)) return errorResponse('OTP login not available for this role', 403, 'FORBIDDEN');
    userId = user.id;
  }

  const windowStart = new Date(Date.now() - OTP_WINDOW_MINUTES * 60000).toISOString();
  const { count } = await db
    .from('otp_codes')
    .select('*', { count: 'exact', head: true })
    .eq('phone_number', phone)
    .gte('created_at', windowStart);

  // 10 OTP requests per phone per 10 minutes → rate limit + block on breach.
  if ((count ?? 0) >= OTP_RATE_LIMIT) {
    await blockKey({
      key: `otp:phone:${phone}`,
      reason: 'OTP request limit reached for this number',
      minutes: OTP_BLOCK_MINUTES,
    });
    await recordSecurityEvent({
      eventType: 'otp_rate_limited',
      key: `otp:phone:${phone}`,
      userId,
      ipAddress: ip,
    });
    if (userId) {
      try {
        await db.from('auth_logs').insert({
          user_id: userId,
          event_type: 'otp_rate_limited',
          ip_address: ip,
        });
      } catch (_) {}
    }
    return errorResponse(
      `OTP request limit reached. Try again in ${OTP_BLOCK_MINUTES} minutes.`,
      429,
      'OTP_RATE_LIMITED',
    );
  }

  await db.from('otp_codes').update({ used: true }).eq('phone_number', phone).eq('used', false);

  const code = Deno.env.get('USE_MOCK_SMS') === 'true'
    ? '123456' // DEV MOCK: fixed OTP so you can test without receiving SMS.
    : String(Math.floor(100000 + Math.random() * 900000));
  const expiresAt = new Date(Date.now() + OTP_EXPIRY_MINUTES * 60000).toISOString();

  await db.from('otp_codes').insert({
    phone_number: phone,
    code,
    expires_at: expiresAt,
    attempts: 0,
    used: false,
  });

  const message = `Your Jireta Loans OTP is: ${code}. Valid for ${OTP_EXPIRY_MINUTES} minutes. Do not share this code.`;
  await sendSms({ to: phone, message, userId: userId ?? undefined });

  if (userId) {
    await db.from('auth_logs').insert({
      user_id: userId,
      event_type: 'otp_sent',
      ip_address: ip,
    });
  }

  return jsonResponse({ message: 'OTP sent successfully', expires_in: OTP_EXPIRY_MINUTES * 60 });
}

// ── [moved from functions/auth-verify-otp/index.ts] ─────────────────────────
async function handleVerifyOtp(req: Request) {
  const { phone_number, code, otp } = await req.json();
  const phone = sanitizeString(String(phone_number ?? ''));
  const otpCode = sanitizeString(String(otp ?? code ?? ''));
  const ip = clientIp(req);

  if (!validatePhone(phone)) return errorResponse('Invalid phone number', 400, 'VALIDATION_ERROR');
  if (!/^\d{6}$/.test(otpCode)) return errorResponse('OTP must be 6 digits', 400, 'VALIDATION_ERROR');

  const db = getAdminClient();

  // If the phone or IP was blocked by the send-OTP guard (10/10min breached),
  // refuse verification attempts too so a blocked key cannot keep probing.
  const phoneBlock = await checkBlock(`otp:phone:${phone}`);
  if (phoneBlock.blocked) {
    return errorResponse(
      'Too many OTP requests. Try again later.',
      429,
      'OTP_RATE_LIMITED',
    );
  }
  const ipBlock = await checkBlock(`otp:ip:${ip}`);
  if (ipBlock.blocked) {
    return errorResponse(
      'Too many OTP requests from this device. Try again later.',
      429,
      'OTP_RATE_LIMITED',
    );
  }

  // Mock OTP (123456) bypasses the stored-OTP checks entirely so ANY phone
  // can sign in for testing without a real SMS delivery — no need to wait for
  // auth-send-otp first or worry about expiry/attempt limits.
  //
  // SECURITY: only accepted when USE_MOCK_SMS is explicitly enabled. In
  // production this env var is unset, so `123456` is treated like any other
  // wrong code and goes through the real stored-OTP verification (a hardcoded
  // bypass would let ANYONE sign in as ANY phone number).
  const isMockOtp = Deno.env.get('USE_MOCK_SMS') === 'true' && otpCode === '123456';

  if (!isMockOtp) {
    const { data: otpRow } = await db
      .from('otp_codes')
      .select('*')
      .eq('phone_number', phone)
      .eq('used', false)
      .gte('expires_at', new Date().toISOString())
      .order('created_at', { ascending: false })
      .limit(1)
      .single();

    if (!otpRow) return errorResponse('OTP expired or not found', 401, 'OTP_EXPIRED');

    if (otpRow.attempts >= MAX_OTP_ATTEMPTS) {
      await db.from('otp_codes').update({ used: true }).eq('id', otpRow.id);
      return errorResponse('Too many attempts. Request a new OTP.', 429, 'RATE_LIMITED');
    }

    if (otpRow.code !== otpCode) {
      await db.from('otp_codes').update({ attempts: otpRow.attempts + 1 }).eq('id', otpRow.id);
      return errorResponse('Invalid OTP code', 401, 'INVALID_OTP');
    }

    await db.from('otp_codes').update({ used: true }).eq('id', otpRow.id);
  }

  const { data: userRow } = await db
    .from('users')
    .select('id, account_status, email, first_name, last_name, phone_number, force_password_change, roles(name)')
    .eq('phone_number', phone)
    .maybeSingle();
  let user = singleWithObjectEmbeds(userRow);

  // Self-registration: an unregistered phone that passes OTP becomes a
  // lender automatically (head-manager pre-registration no longer required).
  if (!user) {
    user = singleWithObjectEmbeds(await selfRegisterLender(db, phone));
    if (!user) return errorResponse('Failed to create account', 500, 'SERVER_ERROR');
  }

  // Build the session using PHONE + password — never a synthetic email in
  // public.users. Self-registered lenders use OTP_<phone>_SECURE; riders and
  // lenders created by staff use the shared staff default password.
  //
  // NOTE: some GoTrue installs (notably local dev) reject phone+password
  // sign-in unless SMS auth is fully provisioned. The temp email
  // `${phone}@jireta.temp` is ONLY an internal GoTrue credential — it never
  // reaches public.users or the app (the response below only exposes the
  // phone). Trying phone first, then email, keeps both local & prod working.
  const phoneE164 = toE164(phone);
  const tempEmail = `${phone}@jireta.temp`;

  const trySignIn = async (password: string) => {
    const attempts = [
      () => db.auth.signInWithPassword({ phone: phoneE164, password }),
      () => db.auth.signInWithPassword({ email: tempEmail, password }),
    ];
    for (const attempt of attempts) {
      const { data, error } = await attempt().catch((e) => {
        console.error('[auth-verify-otp] signInWithPassword error:', e?.message ?? e);
        return { data: null, error: e };
      });
      if (error) {
        console.error('[auth-verify-otp] signInWithPassword:', error.message);
      }
      if (data?.session) return data.session;
    }
    return null;
  };

  let session = null;
  for (const password of [OTP_PASSWORD(phone), DEFAULT_PASSWORD]) {
    session = await trySignIn(password);
    if (session) break;
  }

  // Safety net: never fabricate a token. A magic-link `hashed_token` is NOT a
  // JWT — sending it as a Bearer token makes GoTrue reject every subsequent
  // request with "Invalid JWT format". Recovery only ever issues REAL sessions.
  if (!session) {
    const adminUserId = user?.id;

    // 1) The auth user may already exist with an unknown password. The phone
    //    was just OTP-verified, so reset its password (+ temp email) and sign in.
    if (adminUserId) {
      const { error: updErr } = await db.auth.admin
        .updateUserById(adminUserId, {
          password: OTP_PASSWORD(phone),
          email: tempEmail,
          phone_confirm: true,
          email_confirm: true,
        })
        .catch((e) => {
          console.error('[auth-verify-otp] updateUserById error:', e?.message ?? e);
          return { error: e };
        });
      if (updErr) console.error('[auth-verify-otp] updateUserById:', updErr.message);
      if (!updErr) {
        session = await trySignIn(OTP_PASSWORD(phone));
      }
    }

    // 2) No auth user at all yet — create one, then sign in.
    if (!session) {
      const { data: created, error: createErr } = await db.auth.admin
        .createUser({
          phone: phoneE164,
          email: tempEmail,
          password: OTP_PASSWORD(phone),
          phone_confirm: true,
          email_confirm: true,
          app_metadata: { role: 'lender' },
        })
        .catch((e) => {
          console.error('[auth-verify-otp] createUser error:', e?.message ?? e);
          return { data: null, error: e };
        });
      if (createErr) console.error('[auth-verify-otp] createUser:', createErr.message);
      if (created?.user && !createErr) {
        session = await trySignIn(OTP_PASSWORD(phone));
      }
    }
  }

  if (!session) {
    return errorResponse('Unable to sign in. Please try again.', 500, 'SERVER_ERROR');
  }

  await db.from('auth_logs').insert({
    user_id: user.id,
    event_type: 'login_success',
    ip_address: req.headers.get('x-forwarded-for') ?? 'unknown',
  });
  await db.from('users').update({ last_login_at: new Date().toISOString() }).eq('id', user.id);

  return jsonResponse({
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    user: {
      id: user.id,
      phone,
      role: user?.roles?.name,
      first_name: user?.first_name ?? '',
      last_name: user?.last_name ?? '',
      phone_number: user?.phone_number ?? phone,
      force_password_change: user?.force_password_change,
    },
  });
}