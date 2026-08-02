// supabase/functions/auth-logout/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { getAdminClient } from '../_shared/db.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const db = getAdminClient();
    const body = await req.json().catch(() => ({}));
    if (body.fcm_token !== undefined) {
      await db.from('users').update({ fcm_token: null }).eq('id', user.id);
    }

    await db.from('auth_logs').insert({
      user_id: user.id,
      event_type: 'logout',
      ip_address: req.headers.get('x-forwarded-for') ?? 'unknown',
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
