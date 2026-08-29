// supabase/functions/auth-register/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Employee self-registration with OTP via Resend (email).
// Flow per spec:  Fill form -> Request OTP -> Resend email -> Enter OTP -> Verify -> Create account
// Same UX as forgot-password OTP.
//
// Actions (via ?fn=):
//   send-otp   ?fn=send-otp     -> generate 6-digit OTP, hash, store, email via Resend
//   verify-otp ?fn=verify-otp   -> check 6-digit OTP (and extend grace window)
//   register   ?fn=register     -> validate OTP + create Supabase auth user + public rows
// Default (no fn / unknown) = register, for backwards compat — but now REQUIRES otp param.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import {
  sanitizeString,
  validateEmail,
  validatePhone,
} from '../_shared/validators.ts';
import { hashPassword } from '../_shared/password_hash.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { guardRateLimit, checkRateLimit, checkBlock, blockKey, recordSecurityEvent } from '../_shared/rate_limiter.ts';
import { sendRegistrationOtpEmail } from '../_shared/email.ts';

const REGISTER_RATE_MAX = 5;
const REGISTER_RATE_MINUTES = 60;
const REGISTER_BLOCK_MINUTES = 60;
const DEFAULT_POSITION = 'Staff';

// OTP settings — mirrors auth-password (1 min expiry, 5 attempts, escalating lockout)
const OTP_LENGTH = 6;
const OTP_EXPIRY_MINUTES = 1;
const OTP_MAX_ATTEMPTS = 5;
const MAX_LOCKOUT_MINUTES = 2 * 24 * 60; // 48h

// Abuse detection for OTP SEND (separate from final register IP rate limit)
const REGISTER_OTP_WINDOW_MINUTES = 15;
const REGISTER_OTP_MAX_PER_EMAIL = 5;
const REGISTER_OTP_MAX_PER_IP = 20;
const REGISTER_OTP_BLOCK_MINUTES = 60;

function clientIp(req: Request): string {
  return req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown';
}

function generateOtp(): string {
  const arr = new Uint32Array(1);
  crypto.getRandomValues(arr);
  const n = 100000 + (arr[0] % 900000);
  return String(n);
}

async function hashOtp(otp: string, email: string): Promise<string> {
  const data = new TextEncoder().encode(`${otp}:${email.toLowerCase()}`);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

function lockoutMinutes(attempts: number): number {
  if (attempts <= 2) return 0;
  if (attempts === 3) return 3;
  if (attempts === 4) return 10;
  return Math.min(MAX_LOCKOUT_MINUTES, 10 * Math.pow(10, attempts - 4));
}

async function readRegisterLockout(db: ReturnType<typeof getAdminClient>, email: string) {
  const { data } = await db.from('email_register_lockouts').select('failed_attempts, locked_until').eq('email', email).maybeSingle();
  return { failedAttempts: data?.failed_attempts ?? 0, lockedUntil: data?.locked_until ? new Date(data.locked_until) : null };
}

function lockoutError(lockedUntil: Date, attempts: number): Response {
  const retryAfterSeconds = Math.max(1, Math.ceil((lockedUntil.getTime() - Date.now()) / 1000));
  const minutes = Math.round(retryAfterSeconds / 60);
  const label = minutes > 0 ? `${minutes} minute(s)` : `${retryAfterSeconds} second(s)`;
  return errorResponse(`Too many wrong attempts. Try again in ${label}.`, 429, 'OTP_LOCKED', {
    retry_after_seconds: retryAfterSeconds,
    locked_until: lockedUntil.toISOString(),
    failed_attempts: attempts,
  });
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

    const fn = new URL(req.url).searchParams.get('fn') ?? 'register';
    switch (fn) {
      case 'send-otp':
      case 'request-otp':
        return await handleSendOtp(req);
      case 'verify-otp':
        return await handleVerifyOtp(req);
      case 'register':
        return await handleRegister(req);
      default:
        // Fallback: legacy clients that POST without fn but include otp should still register.
        // If body contains otp, treat as register; otherwise show error.
        return await handleRegister(req);
    }
  } catch (err) {
    console.error('[auth-register] unexpected error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── SEND OTP ───────────────────────────────────────────────────────────────────
async function handleSendOtp(req: Request) {
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return errorResponse('Request body must be valid JSON', 400, 'VALIDATION_ERROR');
  }

  const rawEmail = (body as { email?: unknown }).email ?? (body as { email_address?: unknown }).email_address;
  if (!rawEmail) return errorResponse('Email is required', 400, 'VALIDATION_ERROR');

  const cleanEmail = sanitizeString(rawEmail).trim().toLowerCase();
  if (!validateEmail(cleanEmail)) {
    return errorResponse('Invalid email format', 400, 'VALIDATION_ERROR');
  }

  const ip = clientIp(req);
  const db = getAdminClient();

  // Blocks
  const emailBlock = await checkBlock(`register-otp:${cleanEmail}`);
  if (emailBlock.blocked) return errorResponse('Too many OTP requests for this email. Try again in an hour.', 429, 'REGISTER_OTP_RATE_LIMITED');
  const ipBlock = await checkBlock(`register-otp:ip:${ip}`);
  if (ipBlock.blocked) return errorResponse('Too many OTP requests from this device. Try again later.', 429, 'REGISTER_OTP_RATE_LIMITED');

  const { allowed } = await checkRateLimit({ key: `register_otp:${cleanEmail}`, maxAttempts: REGISTER_OTP_MAX_PER_EMAIL, windowMinutes: REGISTER_OTP_WINDOW_MINUTES });
  if (!allowed) {
    await blockKey({ key: `register-otp:${cleanEmail}`, reason: 'Multiple registration OTP requests', minutes: REGISTER_OTP_BLOCK_MINUTES });
    await recordSecurityEvent({ eventType: 'register_otp_rate_limited', key: `register-otp:${cleanEmail}`, ipAddress: ip, detail: { attempts: REGISTER_OTP_MAX_PER_EMAIL } });
    return errorResponse('Too many OTP requests for this email. Try again in an hour.', 429, 'REGISTER_OTP_RATE_LIMITED');
  }
  const ipResult = await checkRateLimit({ key: `register_otp:ip:${ip}`, maxAttempts: REGISTER_OTP_MAX_PER_IP, windowMinutes: REGISTER_OTP_WINDOW_MINUTES });
  if (!ipResult.allowed) {
    await blockKey({ key: `register-otp:ip:${ip}`, reason: 'Registration OTP flooding', minutes: REGISTER_OTP_BLOCK_MINUTES });
    await recordSecurityEvent({ eventType: 'register_otp_rate_limited', key: `register-otp:ip:${ip}`, ipAddress: ip, detail: { attempts: REGISTER_OTP_MAX_PER_IP } });
    return errorResponse('Too many OTP requests from this device. Try again later.', 429, 'REGISTER_OTP_RATE_LIMITED');
  }

  // Duplicate check — surface 409 before we generate OTP
  const { data: existingEmail } = await db
    .from('users')
    .select('id')
    .ilike('email', cleanEmail)
    .maybeSingle();
  if (existingEmail) return errorResponse('Email already registered', 409, 'DUPLICATE');

  // Generate 6-digit OTP
  const otp = generateOtp();
  const otpHash = await hashOtp(otp, cleanEmail);
  const expiresAt = new Date(Date.now() + OTP_EXPIRY_MINUTES * 60000).toISOString();

  // Invalidate previous unused OTPs and insert new one (trigger also does)
  try {
    await db.from('email_register_otps').update({ used: true }).eq('email', cleanEmail).eq('used', false);
  } catch (_) { /* ignore */ }

  const { error: insertErr } = await db.from('email_register_otps').insert({
    email: cleanEmail,
    otp_hash: otpHash,
    expires_at: expiresAt,
    attempts: 0,
    used: false,
    verified: false,
  });
  if (insertErr) {
    console.error('[auth-register] insert register otp failed:', insertErr.message);
    return errorResponse('Failed to generate verification code', 500, 'SERVER_ERROR');
  }

  // Send via Resend
  const firstName = body.first_name ? sanitizeString(body.first_name) : undefined;
  const lastName = body.last_name ? sanitizeString(body.last_name) : undefined;
  const recipientName = [firstName, lastName].filter(Boolean).join(' ') || undefined;
  const resendApiKey = Deno.env.get('RESEND_API_KEY');
  if (resendApiKey) {
    const sendResult = await sendRegistrationOtpEmail({ to: cleanEmail, otp, recipientName });
    if (!sendResult.ok) console.error('[auth-register] Resend register OTP failed:', sendResult.error);
    else console.log(`[auth-register] OTP via Resend sent to ${cleanEmail} id=${sendResult.id}`);
  } else {
    console.log(`[auth-register] OTP for ${cleanEmail} is ${otp} (RESEND_API_KEY not set, not emailed)`);
  }

  return jsonResponse({ message: 'Verification code sent. Check your email.', expires_in: OTP_EXPIRY_MINUTES * 60 });
}

// ── VERIFY OTP ─────────────────────────────────────────────────────────────────
async function handleVerifyOtp(req: Request) {
  const body = await req.json().catch(() => ({}));
  const { email, otp, code } = body as { email?: unknown; otp?: unknown; code?: unknown };
  const cleanEmail = sanitizeString(email).toLowerCase();
  const cleanOtp = sanitizeString(otp ?? code);
  if (!cleanEmail || !cleanOtp) return errorResponse('Email and OTP are required', 400, 'VALIDATION_ERROR');
  if (!validateEmail(cleanEmail)) return errorResponse('Invalid email format', 400, 'VALIDATION_ERROR');
  if (!/^\d{6}$/.test(cleanOtp)) return errorResponse('OTP must be 6 digits', 400, 'VALIDATION_ERROR');

  const db = getAdminClient();
  const lock = await readRegisterLockout(db, cleanEmail);
  if (lock.lockedUntil && lock.lockedUntil.getTime() > Date.now()) return lockoutError(lock.lockedUntil, lock.failedAttempts);

  const { data: otpRow } = await db.from('email_register_otps')
    .select('*')
    .eq('email', cleanEmail)
    .eq('used', false)
    .gte('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!otpRow) {
    const newAttempts = lock.failedAttempts + 1;
    const minutes = lockoutMinutes(newAttempts);
    const lockedUntil = minutes > 0 ? new Date(Date.now() + minutes * 60000) : null;
    await db.from('email_register_lockouts').upsert({ email: cleanEmail, failed_attempts: newAttempts, locked_until: lockedUntil?.toISOString() ?? null, updated_at: new Date().toISOString() }, { onConflict: 'email' });
    if (lockedUntil) return lockoutError(lockedUntil, newAttempts);
    return errorResponse('Invalid or expired OTP', 400, 'INVALID_OTP');
  }

  if (otpRow.attempts >= OTP_MAX_ATTEMPTS) {
    await db.from('email_register_otps').update({ used: true }).eq('id', otpRow.id);
    const newAttempts = lock.failedAttempts + 1;
    const minutes = lockoutMinutes(newAttempts);
    const lockedUntil = minutes > 0 ? new Date(Date.now() + minutes * 60000) : null;
    await db.from('email_register_lockouts').upsert({ email: cleanEmail, failed_attempts: newAttempts, locked_until: lockedUntil?.toISOString() ?? null, updated_at: new Date().toISOString() }, { onConflict: 'email' });
    if (lockedUntil) return lockoutError(lockedUntil, newAttempts);
    return errorResponse('Too many attempts. Request a new code.', 400, 'INVALID_OTP');
  }

  const submittedHash = await hashOtp(cleanOtp, cleanEmail);
  if (otpRow.otp_hash !== submittedHash) {
    await db.from('email_register_otps').update({ attempts: otpRow.attempts + 1 }).eq('id', otpRow.id);
    const newAttempts = lock.failedAttempts + 1;
    const minutes = lockoutMinutes(newAttempts);
    const lockedUntil = minutes > 0 ? new Date(Date.now() + minutes * 60000) : null;
    await db.from('email_register_lockouts').upsert({ email: cleanEmail, failed_attempts: newAttempts, locked_until: lockedUntil?.toISOString() ?? null, updated_at: new Date().toISOString() }, { onConflict: 'email' });
    if (lockedUntil) return lockoutError(lockedUntil, newAttempts);
    return errorResponse('Invalid OTP code', 400, 'INVALID_OTP');
  }

  // Success — mark verified and extend expiry so user has time to finish registration form submit
  const verifiedGraceExpiresAt = new Date(Date.now() + 10 * 60000).toISOString();
  await db.from('email_register_otps').update({ verified: true, expires_at: verifiedGraceExpiresAt }).eq('id', otpRow.id);
  await db.from('email_register_lockouts').delete().eq('email', cleanEmail);

  return jsonResponse({ message: 'OTP verified successfully', verified: true });
}

// ── REGISTER (requires verified OTP) ───────────────────────────────────────────
async function handleRegister(req: Request) {
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return errorResponse('Request body must be valid JSON', 400, 'VALIDATION_ERROR');
  }

  const {
    first_name, last_name, email, phone_number,
    position, password, gender, civil_status, hired_at,
    otp, code,
  } = body as {
    first_name?: unknown; last_name?: unknown; email?: unknown; phone_number?: unknown;
    position?: unknown; password?: unknown; gender?: unknown; civil_status?: unknown; hired_at?: unknown;
    otp?: unknown; code?: unknown;
  };

  if (!first_name || !last_name || !email || !phone_number || !password) {
    return errorResponse('Required fields missing', 400, 'VALIDATION_ERROR');
  }

  // ── OTP REQUIRED ────────────────────────────────────────────────────────
  const rawOtp = sanitizeString((otp ?? code) as unknown ?? '');
  if (!rawOtp) {
    return errorResponse('OTP is required. Please request a verification code and enter it to register.', 400, 'OTP_REQUIRED');
  }
  if (!/^\d{6}$/.test(rawOtp)) {
    return errorResponse('OTP must be 6 digits', 400, 'VALIDATION_ERROR');
  }

  const cleanEmail = sanitizeString(email).trim().toLowerCase();
  if (!validateEmail(cleanEmail)) {
    return errorResponse('Invalid email format', 400, 'VALIDATION_ERROR');
  }

  const cleanPhone = sanitizeString(phone_number).trim();
  if (!validatePhone(cleanPhone)) {
    return errorResponse('Invalid phone number format (09XXXXXXXXX)', 400, 'VALIDATION_ERROR');
  }

  if (String(password).length < 8) {
    return errorResponse('Password must be at least 8 characters', 400, 'VALIDATION_ERROR');
  }

  const db = getAdminClient();
  const ip = clientIp(req);

  // ── Rate limit per IP for final registration ────────────────────────────
  const rateGuard = await guardRateLimit({
    key: `register:${ip}`,
    maxAttempts: REGISTER_RATE_MAX,
    windowMinutes: REGISTER_RATE_MINUTES,
    blockMinutes: REGISTER_BLOCK_MINUTES,
    blockReason: 'Too many registration attempts',
    eventType: 'register_rate_limited',
    ipAddress: ip,
  });
  if (!rateGuard.allowed) {
    const waitMinutes = rateGuard.block?.retryAfterSeconds
      ? Math.ceil(rateGuard.block.retryAfterSeconds / 60)
      : REGISTER_BLOCK_MINUTES;
    return errorResponse(
      `Too many registration attempts. Try again in ${waitMinutes} minute(s).`,
      429,
      'REGISTER_RATE_LIMITED',
    );
  }

  // ── OTP lockout check BEFORE we burn any work ───────────────────────────
  const lock = await readRegisterLockout(db, cleanEmail);
  if (lock.lockedUntil && lock.lockedUntil.getTime() > Date.now()) return lockoutError(lock.lockedUntil, lock.failedAttempts);

  // ── Duplicate checks (fast user-friendly 409) ───────────────────────────
  const { data: existingEmail } = await db
    .from('users')
    .select('id')
    .ilike('email', cleanEmail)
    .maybeSingle();
  if (existingEmail) return errorResponse('Email already registered', 409, 'DUPLICATE');

  const { data: existingPhone } = await db
    .from('users')
    .select('id')
    .eq('phone_number', cleanPhone)
    .maybeSingle();
  if (existingPhone) return errorResponse('Phone number already registered', 409, 'DUPLICATE');

  // ── Verify OTP for this email ───────────────────────────────────────────
  // Accept either a fresh unused OTP or a pre-verified one (verified=true grace window).
  const { data: otpRow } = await db.from('email_register_otps')
    .select('*')
    .eq('email', cleanEmail)
    .eq('used', false)
    .gte('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!otpRow) {
    const newAttempts = lock.failedAttempts + 1;
    const minutes = lockoutMinutes(newAttempts);
    const lockedUntil = minutes > 0 ? new Date(Date.now() + minutes * 60000) : null;
    await db.from('email_register_lockouts').upsert({ email: cleanEmail, failed_attempts: newAttempts, locked_until: lockedUntil?.toISOString() ?? null, updated_at: new Date().toISOString() }, { onConflict: 'email' });
    if (lockedUntil) return lockoutError(lockedUntil, newAttempts);
    return errorResponse('Invalid or expired OTP. Please request a new code.', 400, 'INVALID_OTP');
  }

  if (otpRow.attempts >= OTP_MAX_ATTEMPTS) {
    await db.from('email_register_otps').update({ used: true }).eq('id', otpRow.id);
    const newAttempts = lock.failedAttempts + 1;
    const minutes = lockoutMinutes(newAttempts);
    const lockedUntil = minutes > 0 ? new Date(Date.now() + minutes * 60000) : null;
    await db.from('email_register_lockouts').upsert({ email: cleanEmail, failed_attempts: newAttempts, locked_until: lockedUntil?.toISOString() ?? null, updated_at: new Date().toISOString() }, { onConflict: 'email' });
    if (lockedUntil) return lockoutError(lockedUntil, newAttempts);
    return errorResponse('Too many attempts. Request a new code.', 400, 'INVALID_OTP');
  }

  const submittedHash = await hashOtp(rawOtp, cleanEmail);
  if (otpRow.otp_hash !== submittedHash) {
    await db.from('email_register_otps').update({ attempts: otpRow.attempts + 1 }).eq('id', otpRow.id);
    const newAttempts = lock.failedAttempts + 1;
    const minutes = lockoutMinutes(newAttempts);
    const lockedUntil = minutes > 0 ? new Date(Date.now() + minutes * 60000) : null;
    await db.from('email_register_lockouts').upsert({ email: cleanEmail, failed_attempts: newAttempts, locked_until: lockedUntil?.toISOString() ?? null, updated_at: new Date().toISOString() }, { onConflict: 'email' });
    if (lockedUntil) return lockoutError(lockedUntil, newAttempts);
    return errorResponse('Invalid OTP code', 400, 'INVALID_OTP');
  }

  // OTP is valid — proceed to create account

  let roleRow: any = null;
  try {
    const { data } = await db.from('roles').select('id, is_archived').eq('name', 'employee').single();
    roleRow = data;
    if ((roleRow as any)?.is_archived === true) return errorResponse('Registration disabled — employee role is archived', 403, 'ROLE_ARCHIVED');
  } catch (_) {
    const { data } = await db.from('roles').select('id').eq('name', 'employee').single();
    roleRow = data;
  }
  if (!roleRow) return errorResponse('Employee role not configured', 500, 'SERVER_ERROR');

  // ── Create the Supabase Auth account ──────────────────────────────────
  const { data: authUser, error: authErr } = await db.auth.admin.createUser({
    email: cleanEmail,
    password: String(password),
    email_confirm: true,
    app_metadata: { role: 'employee' },
  });

  if (authErr || !authUser?.user) {
    if (authErr?.message?.includes('already')) {
      return errorResponse('Email already registered', 409, 'DUPLICATE');
    }
    console.error('[auth-register] auth user creation failed:', authErr?.message);
    return errorResponse('Failed to create account', 500, 'SERVER_ERROR');
  }

  const userId = authUser.user.id;

  // ── public.users row (active so the user can sign in immediately) ─────
  const { error: userErr } = await db.from('users').upsert({
    id: userId,
    role_id: roleRow.id,
    email: cleanEmail,
    phone_number: cleanPhone,
    first_name: sanitizeString(first_name),
    last_name: sanitizeString(last_name),
    account_status: 'active',
    force_password_change: false,
  }, { onConflict: 'id' });

  if (userErr) {
    console.error('[auth-register] users insert failed:', userErr.message);
    await db.auth.admin.deleteUser(userId);
    return errorResponse('Failed to create account', 500, 'SERVER_ERROR');
  }

  // ── employee_profiles row ─────────────────────────────────────────────
  const { error: profileErr } = await db.from('employee_profiles').insert({
    id: userId,
    position: position ? sanitizeString(position) : DEFAULT_POSITION,
    hired_at: hired_at ? String(hired_at).substring(0, 10) : new Date().toISOString().split('T')[0],
    gender: gender ? sanitizeString(gender).toLowerCase() : null,
    civil_status: civil_status ? sanitizeString(civil_status).toLowerCase() : null,
  });

  if (profileErr) {
    console.error('[auth-register] employee_profiles insert failed:', profileErr.message);
    await db.from('users').delete().eq('id', userId);
    await db.auth.admin.deleteUser(userId);
    return errorResponse('Failed to create account', 500, 'SERVER_ERROR');
  }

  // ── Record the chosen password in password_history ────────────────────
  await db.from('password_history').insert({
    user_id: userId,
    password_hash: await hashPassword(userId, String(password)),
  });

  // ── Mark OTP as used and clear lockout ─────────────────────────────────
  await db.from('email_register_otps').update({ used: true, verified: true }).eq('id', otpRow.id);
  await db.from('email_register_lockouts').delete().eq('email', cleanEmail);

  await writeAuditLog({
    performedBy: 'system',
    action: 'employee_registered',
    tableName: 'users',
    recordId: userId,
    newValues: { role: 'employee', email: cleanEmail, phone_number: cleanPhone, first_name: sanitizeString(first_name), last_name: sanitizeString(last_name), position: position ? sanitizeString(position) : DEFAULT_POSITION },
    ipAddress: ip,
  });

  return jsonResponse({
    message: 'Registration successful. You can now sign in.',
    user_id: userId,
  }, 201);
}
