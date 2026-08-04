// supabase/functions/auth-terms-accept/index.ts
// Records one-time Terms & Conditions / Privacy Policy acceptance.
// Sets users.terms_accepted_at and writes a row to terms_consent_logs so the
// acceptance is durable per account and survives sign-out, reinstall, or a
// wiped device-local flag.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { isAuthUser, requireAuth } from '../_shared/auth.ts';
import { errorResponse, handleCors, jsonResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
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
  } catch (err) {
    console.error('auth-terms-accept error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
