// supabase/functions/auth-register/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Public endpoint for EMPLOYEE self-registration on the website app.
//
// Self-registered employees are stored with account_status = 'active' so they
// can sign in immediately after registering (no head manager approval step).
//
// The role is hard-coded to 'employee': the web portal is head_manager /
// employee only, and head managers are bootstrapped via SQL, never via the
// public register form.
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
import { guardRateLimit } from '../_shared/rate_limiter.ts';

const REGISTER_RATE_MAX = 5;
const REGISTER_RATE_MINUTES = 60;
const REGISTER_BLOCK_MINUTES = 60;
const DEFAULT_POSITION = 'Staff';

function clientIp(req: Request): string {
  return req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown';
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return errorResponse('Request body must be valid JSON', 400, 'VALIDATION_ERROR');
    }

    const {
      first_name, last_name, email, phone_number,
      position, password, gender, civil_status, hired_at,
    } = body;

    if (!first_name || !last_name || !email || !phone_number || !password) {
      return errorResponse('Required fields missing', 400, 'VALIDATION_ERROR');
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

    // ── Rate limit per IP so the public form cannot be spammed ────────────
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

    // ── Duplicate checks — Email Uniqueness Validation (security) ─────────
    // Use case-insensitive `ilike` so `Admin@Ex.COM` still collides with
    // `admin@ex.com`.  The DB trigger + partial unique index
    // `uq_users_email_lower` is the final atomic guard; this SELECT gives a
    // fast, user-friendly 409 before we hit the auth service.
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

    const { data: roleRow } = await db
      .from('roles')
      .select('id')
      .eq('name', 'employee')
      .single();
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
    // `position` is optional on the form; fall back to a default because the
    // column is NOT NULL in the database.
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
  } catch (err) {
    console.error('[auth-register] unexpected error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});