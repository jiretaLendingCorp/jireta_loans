// supabase/functions/auth-session/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   auth-refresh-session  →  ?fn=refresh-session
//   auth-terms-accept     →  ?fn=terms-accept
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { isAuthUser, requireAuth } from '../_shared/auth.ts';
import { errorResponse, handleCors, jsonResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import { singleWithObjectEmbeds } from '../_shared/types.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'refresh-session';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'refresh-session':
        // ── [moved from functions/auth-refresh-session/index.ts] ─────────
        return await handleRefreshSession(req);
      case 'terms-accept':
        // ── [moved from functions/auth-terms-accept/index.ts] ────────────
        return await handleTermsAccept(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('auth-session error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/auth-refresh-session/index.ts] ────────────────────
async function handleRefreshSession(req: Request) {
  const { refresh_token } = await req.json();
  if (!refresh_token) return errorResponse('refresh_token is required', 400, 'VALIDATION_ERROR');

  const db = getAdminClient();
  const { data, error } = await db.auth.refreshSession({ refresh_token });
  if (error || !data.session) return errorResponse('Invalid or expired refresh token', 401, 'UNAUTHORIZED');

  const { data: dbUserRow } = await db
    .from('users')
    .select('id, account_status, force_password_change, last_login_at, roles!users_role_id_fkey(name)')
    .eq('id', data.user!.id)
    .single();
  const dbUser = singleWithObjectEmbeds(dbUserRow);

  if (!dbUser) return errorResponse('User not found', 401, 'UNAUTHORIZED');
  if (dbUser.account_status === 'archived') return errorResponse('Account archived', 403, 'ACCOUNT_ARCHIVED');
  // TEMP HOTFIX: role check disabled
  // try { const rName = dbUser?.roles?.name as string | undefined; if (rName) { const { data: _raS } = await db.from('roles').select('is_archived').eq('name', rName).maybeSingle(); if ((_raS as any)?.is_archived === true) return errorResponse('Role is archived — account disabled', 403, 'ROLE_ARCHIVED'); } } catch (_) {}

  // ── 1-hour absolute session: hard expiry, no infinite refresh ──────────
  // After 1 hour from last_login_at, refresh is rejected and user must re-login
  // to get a new 1-hour session. This enforces the required 1h session lifetime.
  // Grace +5m to avoid immediate expiry on clock skew for second login.
  if (dbUser.last_login_at) {
    const elapsed = Date.now() - new Date(dbUser.last_login_at).getTime();
    const ONE_HOUR_MS = 3600 * 1000;
    const GRACE_MS = 5 * 60 * 1000;
    console.log(`[auth-session] refresh check user=${dbUser.id} elapsed=${Math.floor(elapsed/1000)}s last_login_at=${dbUser.last_login_at}`);
    if (elapsed > ONE_HOUR_MS + GRACE_MS) {
      return errorResponse('Session expired after 1 hour, please login again', 401, 'SESSION_EXPIRED');
    }
  }

  return jsonResponse({
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token,
    user: {
      id: dbUser.id,
      role: dbUser?.roles?.name,
      force_password_change: dbUser.force_password_change,
    },
  });
}

// ── [moved from functions/auth-terms-accept/index.ts] ───────────────────────
// Records one-time Terms & Conditions / Privacy Policy acceptance.
// Sets users.terms_accepted_at and writes a row to terms_consent_logs so the
// acceptance is durable per account and survives sign-out, reinstall, or a
// wiped device-local flag.
async function handleTermsAccept(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const body = await req.json().catch(() => ({}));
  const deviceId = body.device_id ?? 'unknown';
  const platform = body.platform ?? 'web';
  const appVersion = body.app_version ?? '1.0.0';

  const db = getAdminClient();

  await db.from('users').update({ terms_accepted_at: new Date().toISOString() }).eq('id', user.id);

  await db.from('terms_consent_logs').insert({
    user_id: user.id,
    device_id: deviceId,
    platform,
    app_version: appVersion,
  });

  return jsonResponse({ message: 'Terms accepted', accepted_at: new Date().toISOString() });
}