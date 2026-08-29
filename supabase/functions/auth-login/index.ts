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
import { guardRateLimit } from '../_shared/rate_limiter.ts';

// ── Persistent, escalating login lockout ───────────────────────────────────
// Stored in `login_lockouts` (keyed by user_id) so the lock survives a browser
// close / restart — only a successful login (or waiting out the lock) clears
// it. Same product spec as the OTP lockout:
//   3 failed attempts  → 3 minutes
//   4 failed attempts  → 10 minutes
//   5+ failed attempts → lockout ×10 per additional attempt (100, 1000, ...)
// The lockout is capped at 48 hours (2 days) so an account can never be
// effectively locked forever by a single escalating streak.
const MAX_LOCKOUT_MINUTES = 2 * 24 * 60; // 48 hours = 2880 minutes
function lockoutMinutes(attempts: number): number {
  if (attempts <= 2) return 0;
  if (attempts === 3) return 3;
  if (attempts === 4) return 10;
  return Math.min(MAX_LOCKOUT_MINUTES, 10 * Math.pow(10, attempts - 4)); // 5 → 100, 6 → 1000, ... capped at 2880
}

async function readLoginLockout(db: ReturnType<typeof getAdminClient>, userId: string) {
  const { data } = await db
    .from('login_lockouts')
    .select('failed_attempts, locked_until')
    .eq('user_id', userId)
    .maybeSingle();
  return {
    failedAttempts: data?.failed_attempts ?? 0,
    lockedUntil: data?.locked_until ? new Date(data.locked_until) : null,
  };
}

function lockoutError(lockedUntil: Date, attempts: number): Response {
  const retryAfterSeconds = Math.max(
    1,
    Math.ceil((lockedUntil.getTime() - Date.now()) / 1000),
  );
  const minutes = Math.round(retryAfterSeconds / 60);
  const label = minutes > 0 ? `${minutes} minute(s)` : `${retryAfterSeconds} second(s)`;
  return errorResponse(
    `Account locked. Too many wrong login attempts. Try again in ${label}.`,
    429,
    'ACCOUNT_LOCKED',
    {
      retry_after_seconds: retryAfterSeconds,
      locked_until: lockedUntil.toISOString(),
      failed_attempts: attempts,
    },
  );
}

// Abuse detection: 20 login attempts per minute per IP+email → block for 15
// minutes. The per-account lockout above still applies on top; this catches
// distributed / IP-scoped brute force earlier.
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

    // ── Resilient role-archived check (works even before migration) ──
    try {
      const roleNameTmp = user?.roles?.name as string | undefined;
      if (roleNameTmp) {
        const { data: roleArchRow } = await db.from('roles').select('is_archived').eq('name', roleNameTmp).maybeSingle();
        // deno-lint-ignore no-explicit-any
        if ((roleArchRow as any)?.is_archived === true) {
          return errorResponse('Role is archived — account disabled', 403, 'ROLE_ARCHIVED');
        }
      }
    } catch (_) { /* column missing before migration → ignore */ }

    if (user.account_status === 'pending') {
      return errorResponse(
        'Account pending approval. Please wait for the head manager to approve your account.',
        403,
        'ACCOUNT_PENDING',
      );
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

    // ── Step 6: persistent lockout check ─────────────────────────────────
    // Server-side per-user counter stored in login_lockouts, survives browser
    // close / restart / refresh. Read BEFORE attempting the sign-in so a locked
    // account cannot even probe credentials.
    const lock = await readLoginLockout(db, user.id);
    if (lock.lockedUntil && lock.lockedUntil.getTime() > Date.now()) {
      return lockoutError(lock.lockedUntil, lock.failedAttempts);
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

      const newFails = lock.failedAttempts + 1;
      const minutes = lockoutMinutes(newFails);
      const lockedUntil = minutes > 0
        ? new Date(Date.now() + minutes * 60000)
        : null;

      await db.from('login_lockouts').upsert({
        user_id: user.id,
        failed_attempts: newFails,
        locked_until: lockedUntil ? lockedUntil.toISOString() : null,
        updated_at: new Date().toISOString(),
      }, { onConflict: 'user_id' });

      await db.from('auth_logs').insert({
        user_id:         user.id,
        event_type:      'login_fail',
        ip_address:      ip,
        failed_attempts: newFails,
        is_locked:       !!lockedUntil,
      });

      if (lockedUntil) return lockoutError(lockedUntil, newFails);
      return errorResponse('Invalid email or password', 401, 'INVALID_CREDENTIALS');
    }

    if (authData.user?.id && authData.user.id !== user.id) {
      console.warn('[auth-login] auth/public user id mismatch', {
        auth_user_id: authData.user.id,
        public_user_id: user.id,
        email: cleanEmail,
        hint: 'Protected functions recover by verified email, but this account should be resynced so public.users.id matches auth.users.id.',
      });
    }

    // ── Step 8: success ───────────────────────────────────────────────────
    // Reset any lockout: a successful login must clear the persistent counter
    // so the escalation restarts from zero.
    await db
      .from('login_lockouts')
      .delete()
      .eq('user_id', user.id);

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

    // Explicitly update last_login_at for absolute 1h hard expiry (don't rely solely on trigger)
    // Ensures second login's timestamp is fresh even if trigger missed, prevents immediate 401 on refresh
    try {
      await db.from('users').update({ last_login_at: new Date().toISOString() }).eq('id', user.id);
    } catch (e) {
      console.warn('[auth-login] last_login_at update failed', e);
    }

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
