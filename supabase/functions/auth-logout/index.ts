// supabase/functions/auth-logout/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser, cleanSessionId } from '../_shared/auth.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeIpAddress } from '../_shared/audit.ts';
import { nowManilaISO } from '../_shared/timezone.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const db = getAdminClient();

    // ── First-login-wins: revoke the ACTIVE session FIRST ────────────────
    // The logout request travels with the anon key (the access token may
    // already be expired), but the stable client session id is unique, so we
    // can revoke the row directly. This is what frees the account for the
    // next login — without it, the row stays active forever and nobody can
    // sign in again.
    const sessionId = cleanSessionId(req.headers.get('x-session-id'));
    if (sessionId) {
      const { error: revokeErr } = await db
        .from('active_sessions')
        .update({ revoked_at: nowManilaISO(), last_seen_at: nowManilaISO() })
        .eq('session_identifier', sessionId)
        .is('revoked_at', null);
      if (revokeErr) {
        console.warn('[auth-logout] active_sessions revoke failed', revokeErr.message);
      }
    } else {
      console.warn('[auth-logout] no x-session-id header — active session NOT revoked');
    }

    // ── Best-effort audit + GoTrue sign-out ──────────────────────────────
    // requireAuth may reject the anon key (UNAUTHORIZED_ANON_TOKEN) or an
    // expired token — that is fine, the revocation above already happened.
    const authResult = await requireAuth(req);
    if (isAuthUser(authResult)) {
      const user = authResult;
      const body = await req.json().catch(() => ({}));
      if (typeof body.fcm_token === 'string' && body.fcm_token.trim() !== '') {
        const token = body.fcm_token.trim();
        // Deactivate this device's push registration (multi-device aware).
        await db
          .from('user_devices')
          .update({ is_active: false, updated_at: new Date().toISOString() })
          .eq('user_id', user.id)
          .eq('fcm_token', token);
        // Clear the legacy single-token column only if it holds exactly this token.
        await db
          .from('users')
          .update({ fcm_token: null })
          .eq('id', user.id)
          .eq('fcm_token', token);
      }

      await db.from('auth_logs').insert({
        user_id: user.id,
        event_type: 'logout',
        ip_address: sanitizeIpAddress(req.headers.get('x-forwarded-for')),
        failed_attempts: 0,
        is_locked: false,
      });
    }

    await db.auth.signOut();

    return jsonResponse({ message: 'Logged out successfully' });
  } catch (err) {
    console.error('auth-logout error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});