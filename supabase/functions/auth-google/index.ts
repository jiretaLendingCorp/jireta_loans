// supabase/functions/auth-google/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Google OAuth exchange for the mobile lender login.
//
// The Flutter app launches Supabase's Google OAuth flow (system browser /
// secure web view), which returns a session bound to the Google auth user.
// This function maps that session to a lender account in public.users:
//   - by email     → an existing lender signs in (repeated Google logins)
//   - auto-register→ an unknown Google account becomes a new lender
//   - non-lender   → rejected — Google sign-in is lender-only
//
// Endpoint: auth-google?fn=exchange
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { errorResponse, handleCors, jsonResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeString } from '../_shared/validators.ts';
import { singleWithObjectEmbeds, type DbClient } from '../_shared/types.ts';

const DEFAULT_ACTION = 'exchange';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'exchange':
        return await handleExchange(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('[auth-google] unexpected error', {
      name:    err instanceof Error ? err.name    : 'UnknownError',
      message: err instanceof Error ? err.message : 'Unknown error',
    });
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

async function handleExchange(req: Request) {
  let accessToken = '';
  let refreshToken = '';
  try {
    const body = await req.json();
    accessToken = sanitizeString(String(body.access_token ?? ''));
    refreshToken = sanitizeString(String(body.refresh_token ?? ''));
  } catch {
    return errorResponse('Request body must be valid JSON', 400, 'VALIDATION_ERROR');
  }

  if (!accessToken) {
    return errorResponse('access_token is required', 400, 'VALIDATION_ERROR');
  }

  const db = getAdminClient();

  // ── Step 1: verify the Google OAuth session token ─────────────────────────
  const { data: { user: authUser }, error: tokenErr } =
    await db.auth.getUser(accessToken);

  if (tokenErr || !authUser) {
    console.error('[auth-google] step=verify_token FAILED', {
      status: tokenErr?.status ?? null,
      msg:    tokenErr?.message ?? null,
    });
    return errorResponse('Invalid or expired session', 401, 'UNAUTHORIZED');
  }

  const email = (authUser.email ?? '').trim().toLowerCase();
  if (!email) {
    return errorResponse('Google account has no email', 400, 'VALIDATION_ERROR');
  }
  // A synthetic temp email means this session is a phone-OTP identity, not a
  // Google account. Exchanging it would try to self-register with the temp
  // email and fail the users_email_or_phone check. Reject it with a clear
  // message instead.
  if (email.endsWith('@jireta.temp')) {
    return errorResponse(
      'This account is not linked to Google. Sign in with your phone number instead.',
      400,
      'VALIDATION_ERROR',
    );
  }

  // ── Step 2: resolve the lender by email (or auto-register) ────────────────
  const { data: userRow } = await db
    .from('users')
    .select('id, email, first_name, last_name, account_status, force_password_change, roles(name)')
    .eq('email', email)
    .maybeSingle();
  let user = singleWithObjectEmbeds(userRow);

  if (!user) {
    // Google sign-in is lender-only: unknown accounts self-register as lenders
    // (mirrors the OTP self-registration flow for phone-based lenders).
    user = singleWithObjectEmbeds(
      await selfRegisterGoogleLender(db, authUser.id, email, authUser.user_metadata),
    );
    if (!user) return errorResponse('Failed to create account', 500, 'SERVER_ERROR');
  }

  const role = user?.roles?.name;

  if (role !== 'lender') {
    return errorResponse(
      'Google sign-in is only available for lender accounts',
      403,
      'FORBIDDEN',
    );
  }

  if (user.account_status === 'archived') {
    return errorResponse('Account archived', 403, 'ACCOUNT_ARCHIVED');
  }

  // ── Step 3: guard against auth.id ↔ users.id mismatches ──────────────────
  // Every downstream Edge Function resolves public.users by the JWT's user id
  // (see _shared/auth.ts). The token below is bound to authUser.id, so the
  // mapped users row MUST share that id. This only diverges for accounts
  // registered outside the Google flow (e.g. phone-OTP lenders) whose Google
  // email was set later.
  if (user.id !== authUser.id) {
    console.error('[auth-google] step=id_mismatch', {
      users_id: user.id,
      auth_id:  authUser.id,
    });
    return errorResponse(
      'This email is linked to an existing account. Please contact our office to link your Google account.',
      409,
      'ACCOUNT_LINKED',
    );
  }

  // ── Step 4: issue a fresh session so the app stores refreshable tokens ────
  // The mobile PKCE OAuth flow always returns a refresh token. If one is not
  // provided, fall back to the verified access token rather than failing.
  let accessTokenOut = accessToken;
  let refreshTokenOut = refreshToken;

  if (refreshToken) {
    const { data: sessionData, error: refreshErr } =
      await db.auth.refreshSession({ refresh_token: refreshToken });

    if (refreshErr || !sessionData?.session) {
      console.error('[auth-google] step=refresh_session FAILED', {
        status: refreshErr?.status ?? null,
        msg:    refreshErr?.message ?? null,
      });
      return errorResponse('Invalid or expired session', 401, 'UNAUTHORIZED');
    }
    accessTokenOut  = sessionData.session.access_token;
    refreshTokenOut = sessionData.session.refresh_token;
  }

  // Best-effort audit log. Must never fail the exchange: a missing
  // x-forwarded-for header would otherwise make this insert throw on the
  // INET column and convert a successful sign-in into a 500.
  try {
    await db.from('auth_logs').insert({
      user_id:      user.id,
      event_type:   'login_success',
      ip_address:   req.headers.get('x-forwarded-for') ?? undefined,
    });
  } catch (err) {
    console.error('[auth-google] auth_log insert failed', err);
  }

  return jsonResponse({
    access_token:  accessTokenOut,
    refresh_token: refreshTokenOut,
    user: {
      id:                    user.id,
      email:                 user.email,
      first_name:            user.first_name  ?? '',
      last_name:             user.last_name   ?? '',
      role,
      force_password_change: user.force_password_change,
    },
  });
}

async function selfRegisterGoogleLender(
  db: DbClient,
  authUserId: string,
  email: string,
  metadata: Record<string, unknown>,
) {
  const { data: roleData, error: roleErr } = await db
    .from('roles')
    .select('id')
    .eq('name', 'lender')
    .single();
  if (roleErr || !roleData) {
    console.error('[auth-google] step=resolve_lender_role FAILED', {
      msg: roleErr?.message ?? 'lender role not found',
    });
    return null;
  }

  const fullName   = sanitizeString(String(metadata?.full_name ?? ''));
  const givenName  = sanitizeString(String(metadata?.given_name ?? ''));
  const familyName = sanitizeString(String(metadata?.family_name ?? ''));
  const parts      = fullName.split(' ').filter(Boolean);

  const first_name = sanitizeString(parts[0] ?? givenName);
  const last_name  = sanitizeString(parts.slice(1).join(' ') || familyName);

  const { data: newUser, error: userErr } = await db
    .from('users')
    .insert({
      id:                    authUserId,
      role_id:               roleData.id,
      email,
      phone_number:          null,
      first_name,
      last_name,
      account_status:        'active',
      force_password_change: false,
      created_by:            null,
    })
    .select('id, email, first_name, last_name, account_status, force_password_change, roles(name)')
    .single();

  if (userErr || !newUser) {
    console.error('[auth-google] step=create_user FAILED', {
      reason: userErr?.message ?? 'insert returned no row',
    });
    return null;
  }

  const { error: profileErr } = await db.from('lender_profiles').insert({
    id:         newUser.id,
    account_upgrade_status: 'not_submitted',
  });
  if (profileErr) {
    await Promise.resolve(db.from('users').delete().eq('id', newUser.id)).catch(() => {});
    console.error('[auth-google] step=create_profile FAILED', {
      reason: profileErr.message,
    });
    return null;
  }

  return newUser;
}
