
// supabase/functions/auth-refresh-session/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const { refresh_token } = await req.json();
    if (!refresh_token) return errorResponse('refresh_token is required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();
    const { data, error } = await db.auth.refreshSession({ refresh_token });
    if (error || !data.session) return errorResponse('Invalid or expired refresh token', 401, 'UNAUTHORIZED');

    const { data: dbUser } = await db
      .from('users')
      .select('id, account_status, force_password_change, roles(name)')
      .eq('id', data.user!.id)
      .single();

    if (!dbUser) return errorResponse('User not found', 401, 'UNAUTHORIZED');
    if (dbUser.account_status === 'suspended') return errorResponse('Account suspended', 403, 'ACCOUNT_SUSPENDED');
    if (dbUser.account_status === 'archived') return errorResponse('Account archived', 403, 'ACCOUNT_ARCHIVED');

    return jsonResponse({
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
      user: {
        id: dbUser.id,
        role: (dbUser as any).roles?.name,
        force_password_change: dbUser.force_password_change,
      },
    });
  } catch (err) {
    console.error('auth-refresh-session error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});