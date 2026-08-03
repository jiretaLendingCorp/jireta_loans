// supabase/functions/auth-force-change-password/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { isAuthUser, requireAuth } from '../_shared/auth.ts';
import { errorResponse, handleCors, jsonResponse } from '../_shared/cors.ts';
import { getAdminClient, getAnonClient } from '../_shared/db.ts';
import { sanitizeString, validatePasswordComplexity } from '../_shared/validators.ts';

const PASSWORD_HISTORY_LIMIT = 5;

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;

    // FIX: Flutter sends both `current_password` and `new_password`.
    // The previous version only read `new_password` and never validated
    // `current_password`, meaning anyone with a valid JWT could change any
    // account's password without knowing the old one.
    const { current_password, new_password } = await req.json();

    if (!new_password) {
      return errorResponse('new_password is required', 400, 'VALIDATION_ERROR');
    }
    if (!current_password) {
      return errorResponse('current_password is required', 400, 'VALIDATION_ERROR');
    }

    const cleanNew = sanitizeString(new_password);
    const complexity = validatePasswordComplexity(cleanNew);
    if (!complexity.valid) {
      return errorResponse(complexity.message!, 400, 'VALIDATION_ERROR');
    }

    // Verify the current password is correct before allowing the change.
    // Use the anon client (signInWithPassword) — it validates against auth.users.
    const anonClient = getAnonClient();
    const { error: verifyErr } = await anonClient.auth.signInWithPassword({
      email: authResult.email ?? '',
      password: current_password,
    });
    if (verifyErr) {
      return errorResponse('Current password is incorrect', 401, 'INVALID_CREDENTIALS');
    }

    const db = getAdminClient();

    const { data: user } = await db
      .from('users')
      .select('id, force_password_change')
      .eq('id', authResult.id)
      .single();

    if (!user) return errorResponse('User not found', 404, 'NOT_FOUND');
    if (!user.force_password_change) {
      return errorResponse('Password change not required', 400, 'VALIDATION_ERROR');
    }

    // Check password history
    const { data: history } = await db
      .from('password_history')
      .select('password_hash')
      .eq('user_id', authResult.id)
      .order('created_at', { ascending: false })
      .limit(PASSWORD_HISTORY_LIMIT);

    for (const h of history ?? []) {
      if (h.password_hash === cleanNew) {
        return errorResponse(
          `Cannot reuse last ${PASSWORD_HISTORY_LIMIT} passwords`,
          400,
          'PASSWORD_REUSE',
        );
      }
    }

    const { error: updateErr } = await db.auth.admin.updateUserById(authResult.id, {
      password: cleanNew,
    });

    if (updateErr) return errorResponse('Failed to update password', 500, 'SERVER_ERROR');

    await db.from('users')
      .update({ force_password_change: false })
      .eq('id', authResult.id);

    await db.from('password_history').insert({
      user_id: authResult.id,
      password_hash: cleanNew,
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
