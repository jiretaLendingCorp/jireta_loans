// supabase/functions/device-tokens/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// FCM device-token management for the CURRENT authenticated user.
//
//   ?fn=register   — upsert (user_id, fcm_token) into user_devices, marking
//                    it active. Supports MULTIPLE devices per user. Also keeps
//                    the legacy users.fcm_token column in sync. If the same
//                    token was previously registered by another user, that
//                    old binding is deactivated (a token belongs to one
//                    device, and that device is logged into one account).
//   ?fn=unregister — deactivate the given token for this user (called on
//                    logout); the legacy users.fcm_token is cleared if it
//                    matches.
//
// Only the authenticated user's own devices may be touched (requireAuth).
// Token values are validated (length/printability) but never logged.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { getAdminClient } from '../_shared/db.ts';

const PLATFORMS = ['android', 'ios', 'web'];

function sanitizeToken(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const token = raw.trim();
  if (token.length === 0 || token.length > 4096) return null;
  // FCM registration tokens are URL-safe strings (A-Z a-z 0-9 _ - : . % and
  // occasionally / or =). Reject control characters / whitespace.
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f]/.test(token)) return null;
  return token;
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? 'register';
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const db = getAdminClient();
    const body = await req.json().catch(() => ({}));

    switch (fn) {
      case 'register': {
        const fcmToken = sanitizeToken(body.fcm_token);
        if (!fcmToken) {
          return errorResponse('Valid fcm_token is required', 400, 'INVALID_TOKEN');
        }

        let platform = 'android';
        if (typeof body.platform === 'string' && PLATFORMS.includes(body.platform)) {
          platform = body.platform;
        }
        const appVersion =
          typeof body.app_version === 'string' ? body.app_version.slice(0, 50) : null;

        // A token belongs to one physical device → drop any stale binding to
        // another account before (re)registering it for this user.
        await db
          .from('user_devices')
          .update({ is_active: false })
          .eq('fcm_token', fcmToken)
          .neq('user_id', user.id);

        const { error: upsertErr } = await db.from('user_devices').upsert(
          {
            user_id: user.id,
            fcm_token: fcmToken,
            platform,
            app_version: appVersion,
            is_active: true,
            last_seen_at: new Date().toISOString(),
          },
          { onConflict: 'user_id,fcm_token' }
        );
        if (upsertErr) {
          console.error('[device-tokens] upsert failed:', upsertErr.message);
          return errorResponse('Failed to register device', 500, 'DB_ERROR');
        }

        // Keep the legacy single-token column in sync so any remaining reader
        // (e.g. reports/views) still sees the latest token.
        await db.from('users').update({ fcm_token: fcmToken }).eq('id', user.id);

        return jsonResponse({ success: true });
      }
      case 'unregister': {
        const fcmToken = sanitizeToken(body.fcm_token);
        if (!fcmToken) {
          return errorResponse('Valid fcm_token is required', 400, 'INVALID_TOKEN');
        }

        await db
          .from('user_devices')
          .update({ is_active: false, updated_at: new Date().toISOString() })
          .eq('user_id', user.id)
          .eq('fcm_token', fcmToken);

        // Clear the legacy column only if it holds exactly this token.
        await db
          .from('users')
          .update({ fcm_token: null })
          .eq('id', user.id)
          .eq('fcm_token', fcmToken);

        return jsonResponse({ success: true });
      }
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('device-tokens error:', err instanceof Error ? err.message : err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});