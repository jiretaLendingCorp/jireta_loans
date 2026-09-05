// supabase/functions/auth-logout/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeIpAddress } from '../_shared/audit.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const db = getAdminClient();
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

    await db.auth.signOut();

    return jsonResponse({ message: 'Logged out successfully' });
  } catch (err) {
    console.error('auth-logout error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
