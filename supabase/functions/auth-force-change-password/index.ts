// supabase/functions/auth-force-change-password/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePasswordComplexity, sanitizeString } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';

const PASSWORD_HISTORY_LIMIT = 5;

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;

    const { new_password } = await req.json();
    if (!new_password) return errorResponse('new_password is required', 400, 'VALIDATION_ERROR');

    const complexity = validatePasswordComplexity(sanitizeString(new_password));
    if (!complexity.valid) return errorResponse(complexity.message!, 400, 'VALIDATION_ERROR');

    const db = getAdminClient();

    const { data: user } = await db
      .from('users')
      .select('id, force_password_change')
      .eq('id', authResult.id)
      .single();

    if (!user) return errorResponse('User not found', 404, 'NOT_FOUND');
    if (!user.force_password_change) return errorResponse('Password change not required', 400, 'VALIDATION_ERROR');

    const { data: history } = await db
      .from('password_history')
      .select('password_hash')
      .eq('user_id', authResult.id)
      .order('created_at', { ascending: false })
      .limit(PASSWORD_HISTORY_LIMIT);

    for (const h of history ?? []) {
      if (h.password_hash === new_password) {
        return errorResponse(`Cannot reuse last ${PASSWORD_HISTORY_LIMIT} passwords`, 400, 'PASSWORD_REUSE');
      }
    }

    const { error: updateErr } = await db.auth.admin.updateUserById(authResult.id, {
      password: new_password,
    });

    if (updateErr) return errorResponse('Failed to update password', 500, 'SERVER_ERROR');

    await db.from('users').update({ force_password_change: false }).eq('id', authResult.id);

    await db.from('password_history').insert({
      user_id: authResult.id,
      password_hash: new_password,
    });

    await db.from('auth_logs').insert({
      user_id: authResult.id,
      event_type: 'force_password_changed',
      ip_address: req.headers.get('x-forwarded-for') ?? 'unknown',
    });

    await writeAuditLog({
      performedBy: authResult.id,
      action: 'force_password_changed',
      tableName: 'users',
      recordId: authResult.id,
      ipAddress: req.headers.get('x-forwarded-for') ?? undefined,
    });

    return jsonResponse({ message: 'Password changed successfully' });
  } catch (err) {
    console.error('auth-force-change-password error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});