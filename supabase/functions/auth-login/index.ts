// supabase/functions/auth-login/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import {
  errorResponse,
  handleCors,
  jsonResponse,
} from '../_shared/cors.ts';
import {
  getAdminClient,
  getAnonClient,
} from '../_shared/db.ts';
import {
  sanitizeString,
  validateEmail,
} from '../_shared/validators.ts';
import { singleWithObjectEmbeds } from '../_shared/types.ts';
import { guardRateLimit, recordSecurityEvent } from '../_shared/rate_limiter.ts';

const MAX_FAILED      = 5;
const LOCKOUT_MINUTES = 15;

// Abuse detection: 20 login attempts per minute per IP+email → block for 15
// minutes. The existing per-account lockout (5 fails / 15 min) still applies
// on top; this catches distributed / IP-scoped brute force earlier.
const LOGIN_RATE_MAX   = 20;
const LOGIN_RATE_MINUTE = 1;
const LOGIN_BLOCK_MINUTES = 15;

function clientIp(req: Request): string {
  return req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown';
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    // ── Step 1: parse body ────────────────────────────────────────────────
    let email: string, password: string;
    try {
      ({ email, password } = await req.json());
    } catch {
      return errorResponse('Request body must be valid JSON', 400, 'VALIDATION_ERROR');
    }

    if (!email || !password) {
      return errorResponse('Email and password are required', 400, 'VALIDATION_ERROR');
    }

    const cleanEmail = sanitizeString(email).trim().toLowerCase();

    if (!validateEmail(cleanEmail)) {
      return errorResponse('Invalid email format', 400, 'VALIDATION_ERROR');
    }

    // ── Step 2: create clients ────────────────────────────────────────────
    const db       = getAdminClient();
    const anonAuth = getAnonClient();
    const ip       = clientIp(req);

    // ── Step 2.5: abuse detection (IP-scoped brute force) ────────────────
    // 20 attempts/min per IP+email → temporary block. Checked BEFORE any
    // database work so a flood of bad logins cannot hammer the DB.
    const rateKey = `login:${ip}:${cleanEmail}`;
    const rateGuard = await guardRateLimit({
      key: rateKey,
      maxAttempts: LOGIN_RATE_MAX,
      windowMinutes: LOGIN_RATE_MINUTE,
      blockMinutes: LOGIN_BLOCK_MINUTES,
      blockReason: 'Too many login attempts',
      eventType: 'login_rate_limited',
      ipAddress: ip,
    });
    if (!rateGuard.allowed) {
      const waitMinutes = rateGuard.block?.retryAfterSeconds
        ? Math.ceil(rateGuard.block.retryAfterSeconds / 60)
        : LOGIN_BLOCK_MINUTES;
      // Record for the audit trail if the email maps to a known account.
      const { data: blockedUser } = await db
        .from('users')
        .select('id')
        .eq('email', cleanEmail)
        .maybeSingle();
      if (blockedUser?.id) {
        try {
          await db.from('auth_logs').insert({
            user_id: blockedUser.id,
            event_type: 'login_rate_limited',
            ip_address: ip,
          });
        } catch (_) {}
      }
      return errorResponse(
        `Too many login attempts. Try again in ${waitMinutes} minute(s).`,
        429,
        'LOGIN_RATE_LIMITED',
      );
    }

    // ── Step 3: look up user in public.users ──────────────────────────────
    // NOTE: This is the custom users table, NOT auth.users.
    // If the user was created directly via the Supabase Dashboard (Auth →
    // Add User), they will only exist in auth.users, not here → 401.
    // Users MUST be created through the users-create-employee / users-create-
    // rider / users-create-lender Edge Functions, or bootstrapped via the
    // 00006_bootstrap_head_manager.sql migration script.
   const { data: userRow, error: userErr } = await db
  .from('users')
  .select('id, email, first_name, last_name, account_status, force_password_change, roles(name)')
  .eq('email', cleanEmail)
  .single();
  const user = singleWithObjectEmbeds(userRow);

    if (userErr || !user) {
      // ── DIAGNOSTIC ────────────────────────────────────────────────────────
      // If you keep seeing 401 with correct credentials, open Supabase Logs
      // and look for this message. "code: PGRST116" means zero rows returned
      // (the user has no row in public.users). Fix: run the bootstrap SQL or
      // re-create the user through the correct Edge Function.
      console.error('[auth-login] step=users_lookup FAILED', {
        reason: userErr?.message ?? 'no row in public.users for this email',
        code:   userErr?.code   ?? 'NOT_FOUND',
        hint:   'User exists in auth.users but not in public.users? Run 00006_bootstrap_head_manager.sql.',
      });
      return errorResponse('Invalid email or password', 401, 'INVALID_CREDENTIALS');
    }

    // ── Step 4: account status ────────────────────────────────────────────
    if (user.account_status === 'archived') {
      return errorResponse('Account archived', 403, 'ACCOUNT_ARCHIVED');
    }

    // ── Step 5: role check ────────────────────────────────────────────────
    const role = user?.roles?.name as string | undefined;

    if (!role) {
      // roles(name) join returned null → role_id FK is broken or roles table
      // has no matching row for this user's role_id.
      console.error('[auth-login] step=role_lookup FAILED', {
        user_id: user.id,
        hint: 'roles(name) join returned null. Check that public.roles contains the role referenced by this user.',
      });
      return errorResponse('User role not configured', 500, 'SERVER_ERROR');
    }

    if (!['head_manager', 'employee'].includes(role)) {
      console.error('[auth-login] step=role_check FAILED', {
        role,
        hint: 'Web portal is for head_manager and employee only.',
      });
      return errorResponse('Web login not available for this role', 403, 'FORBIDDEN');
    }

    // ── Step 6: lockout check ─────────────────────────────────────────────
    const { data: recentLogs } = await db
      .from('auth_logs')
      .select('id, is_locked, created_at')
      .eq('user_id', user.id)
      .eq('event_type', 'login_fail')
      .gte(
        'created_at',
        new Date(Date.now() - LOCKOUT_MINUTES * 60 * 1000).toISOString(),
      )
      .order('created_at', { ascending: false });

    const failCount = recentLogs?.length ?? 0;
    const isLocked  = recentLogs?.some((l) => l.is_locked) ?? false;

    if (isLocked || failCount >= MAX_FAILED) {
      return errorResponse(
        `Account locked. Try again in ${LOCKOUT_MINUTES} minutes.`,
        429,
        'ACCOUNT_LOCKED',
      );
    }

    // ── Step 7: Supabase Auth sign-in ─────────────────────────────────────
    // This is where a wrong password, an unconfirmed email, or a missing
    // auth.users row will surface.
    const { data: authData, error: authErr } =
      await anonAuth.auth.signInWithPassword({ email: cleanEmail, password });

    if (authErr || !authData.session) {
      console.error('[auth-login] step=sign_in_password FAILED', {
        // Common causes:
        //   "Invalid login credentials"  → wrong password, OR the auth.users
        //     row was never created (only public.users exists).
        //   "Email not confirmed"        → Supabase Auth requires email
        //     confirmation. Disable it in Dashboard → Auth → Settings, or
        //     pass email_confirm: true when calling auth.admin.createUser().
        status: authErr?.status ?? null,
        name:   authErr?.name   ?? null,
        msg:    authErr?.message ?? null,
      });

      const newFails = failCount + 1;
      await db.from('auth_logs').insert({
        user_id:         user.id,
        event_type:      'login_fail',
        ip_address:      ip,
        failed_attempts: newFails,
        is_locked:       newFails >= MAX_FAILED,
      });

      return errorResponse('Invalid email or password', 401, 'INVALID_CREDENTIALS');
    }

    // ── Step 8: success ───────────────────────────────────────────────────
    // Reset any lockout: a successful login must clear the recently
    // accumulated login_fail / account_locked rows. Without this, fails from a
    // few minutes ago (or a stray duplicate request) permanently keep the
    // account locked even though the user just signed in successfully.
    await db
      .from('auth_logs')
      .delete()
      .eq('user_id', user.id)
      .in('event_type', ['login_fail', 'account_locked']);

    // Clear the sliding-window abuse counter too so an already-authenticated
    // user is never caught by the 20/min IP+email guard on their next sign-in.
    await db
      .from('rate_limit_logs')
      .delete()
      .eq('key', rateKey);

    await db.from('auth_logs').insert({
      user_id:         user.id,
      event_type:      'login_success',
      ip_address:      ip,
      failed_attempts: 0,
      is_locked:       false,
    });

   return jsonResponse({
  access_token:  authData.session.access_token,
  refresh_token: authData.session.refresh_token,
  user: {
    id:                    user.id,
    email:                 user.email,
    first_name:            user.first_name  ?? '',   // FIX: was missing → avatar showed 'U'
    last_name:             user.last_name   ?? '',   // FIX: was missing
    role,
    force_password_change: user.force_password_change,
  },
});

  } catch (err) {
    console.error('[auth-login] unexpected error', {
      name:    err instanceof Error ? err.name    : 'UnknownError',
      message: err instanceof Error ? err.message : 'Unknown error',
    });
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
