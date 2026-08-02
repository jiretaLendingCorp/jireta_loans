// supabase/functions/auth-reset-password/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePasswordComplexity, sanitizeString } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const { token, new_password } = await req.json();
    if (!token || !new_password) {
      return errorResponse('Token and new_password are required', 400, 'VALIDATION_ERROR');
    }

    const pw = sanitizeString(new_password);
    const check = validatePasswordComplexity(pw);
    if (!check.valid) return errorResponse(check.message!, 400, 'VALIDATION_ERROR');

    const db = getAdminClient();

    const { data, error } = await db.auth.admin.getUserById(token);
    if (error || !data.user) {
      return errorResponse('Invalid or expired reset token', 400, 'INVALID_TOKEN');
    }

    const userId = data.user.id;

    const { data: hist } = await db
      .from('password_history')
      .select('password_hash')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(5);

    const { error: updateError } = await db.auth.admin.updateUserById(userId, { password: pw });
    if (updateError) return errorResponse('Failed to reset password', 500, 'SERVER_ERROR');

    await db.from('password_history').insert({ user_id: userId, password_hash: 'hashed' });

    await writeAuditLog({
      performedBy: userId,
      action: 'password_reset',
      tableName: 'users',
      recordId: userId,
      ipAddress: req.headers.get('x-forwarded-for') ?? 'unknown',
    });

    return jsonResponse({ message: 'Password reset successfully' });
  } catch (err) {
    console.error('auth-reset-password error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});