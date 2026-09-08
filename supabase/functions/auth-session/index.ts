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
import {
  cleanSessionId,
  isAuthUser,
  requireAuth,
  sessionIdentifierFromToken,
} from '../_shared/auth.ts';
import { errorResponse, handleCors, jsonResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import { singleWithObjectEmbeds } from '../_shared/types.ts';
import { nowManilaISO } from '../_shared/timezone.ts';

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
      case 'ping':
        // Session heartbeat: the app pings ~every 60s while open. requireAuth
        // → validate_active_session bumps last_seen_at, so an open app keeps
        // its row "recently seen" and continues to block other logins
        // (first-login-wins). A force-closed app stops pinging and its row
        // expires after 5 minutes.
        return await handlePing(req);
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
  // session_id is the client-generated stable identifier (see cleanSessionId).
  // The refresh NEVER claims — it only checks that this sign-in is still the
  // active one, using the SAME stable id the client claimed at login so a
  // token rotation can never self-revoke the session.
  const { refresh_token, session_id: bodySessionId } = await req.json();
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

  // ── Single-active-session check ────────────────────────────────────────
  // The refresh call itself never claims a session (refreshing is just the
  // SAME sign-in rotating its token — claiming would revoke it). Instead we
  // check that this sign-in is still the active one. Routine authenticated
  // requests bump last_seen_at via validate_active_session in _shared/auth.ts
  // (last_login_at stays the real last successful login).
  const sessionIdentifier =
    cleanSessionId(bodySessionId) ??
    sessionIdentifierFromToken(data.session.access_token);
  const { data: activeRow, error: activeErr } = await db
    .from('active_sessions')
    .select('last_seen_at')
    .eq('user_id', dbUser.id)
    .eq('session_identifier', sessionIdentifier)
    .is('revoked_at', null)
    .maybeSingle();

  // Fail-open on infrastructure errors (table/function missing): log loudly
  // and allow the refresh. A CLEAN missing row means this sign-in was
  // superseded by a newer login → revoke. The client owns the idle-expiry
  // timer; the server no longer double-enforces it (a stale last_seen_at for
  // benign reasons, e.g. an offline device, must not kill a healthy session).
  if (activeErr) {
    console.error(
      '[auth-session] active_sessions query failed — single-session enforcement degraded, allowing refresh',
      {
        userId: dbUser.id,
        sessionIdentifier,
        error: activeErr.message,
        code: (activeErr as { code?: string })?.code ?? null,
      },
    );
  } else if (!activeRow) {
    // Clean miss: either superseded (an active_sessions row exists with a
    // different identifier → revoke) or the claim at login never persisted
    // (no row at all → allow, enforcement degraded). Never lazily create the
    // row here: a lazy claim would revoke OTHER devices whose logins also
    // skipped the claim, causing false "Session Ended" on every account.
    const { data: anyRow, error: anyErr } = await db
      .from('active_sessions')
      .select('id')
      .eq('user_id', dbUser.id)
      .maybeSingle();
    if (anyErr) {
      console.error(
        '[auth-session] active_sessions existence check failed — allowing refresh',
        {
          userId: dbUser.id,
          error: anyErr.message,
          code: (anyErr as { code?: string })?.code ?? null,
        },
      );
    } else if (!anyRow) {
      console.warn(
        '[auth-session] refresh miss with no active_sessions row — allowing (enforcement degraded, no lazy claim)',
        { userId: dbUser.id, sessionIdentifier },
      );
    } else {
      return errorResponse(
        'Your account was signed in on another device. This session has been logged out for security.',
        401,
        'SESSION_REVOKED',
      );
    }
  }

  // Keep the active record fresh and mark this device as active/seen now.
  try {
    const { error: touchErr } = await db
      .from('active_sessions')
      .update({ last_seen_at: nowManilaISO() })
      .eq('user_id', dbUser.id)
      .eq('session_identifier', sessionIdentifier)
      .is('revoked_at', null);
    if (touchErr) console.warn('[auth-session] last_seen_at bump failed', touchErr.message);
  } catch (e) {
    console.warn('[auth-session] last_seen_at bump failed', e);
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

// ── Session heartbeat ────────────────────────────────────────────────────────
async function handlePing(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  return jsonResponse({ ok: true });
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

  await db.from('users').update({ terms_accepted_at: nowManilaISO() }).eq('id', user.id);

  await db.from('terms_consent_logs').insert({
    user_id: user.id,
    device_id: deviceId,
    platform,
    app_version: appVersion,
  });

  return jsonResponse({ message: 'Terms accepted', accepted_at: nowManilaISO() });
}