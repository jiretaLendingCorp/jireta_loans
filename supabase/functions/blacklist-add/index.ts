// supabase/functions/blacklist-add/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { validateUUID, sanitizeString } from '../_shared/validators.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const body = await req.json().catch(() => ({}));
    const { lender_id, reason } = body;

    if (!lender_id || !validateUUID(lender_id)) {
      return errorResponse('Valid lender_id is required', 400, 'VALIDATION_ERROR');
    }
    if (!reason || reason.trim().length < 5) {
      return errorResponse('A reason of at least 5 characters is required', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();

    const { data: lender } = await db
      .from('users')
      .select('id, first_name, last_name, roles(name)')
      .eq('id', lender_id)
      .single();

    if (!lender || (lender as any).roles?.name !== 'lender') {
      return errorResponse('Lender not found', 404, 'NOT_FOUND');
    }

    const { data: existing } = await db
      .from('blacklist')
      .select('id, is_active')
      .eq('lender_id', lender_id)
      .eq('is_active', true)
      .single();

    if (existing) {
      return errorResponse('Lender is already blacklisted', 400, 'DUPLICATE');
    }

    const { data: blacklistEntry, error: blErr } = await db
      .from('blacklist')
      .insert({
        lender_id,
        reason: sanitizeString(reason),
        added_by: authResult.id,
        is_active: true,
      })
      .select()
      .single();

    if (blErr) throw blErr;

    await db
      .from('lender_profiles')
      .update({ is_blacklisted: true, blacklist_reason: sanitizeString(reason), blacklisted_by: authResult.id, blacklisted_at: new Date().toISOString() })
      .eq('id', lender_id);

    await writeAuditLog({
      performedBy: authResult.id,
      action: 'blacklist_add',
      tableName: 'blacklist',
      recordId: blacklistEntry.id,
      newValues: { lender_id, reason },
    });

    await sendPushNotification({
      userId: lender_id,
      title: 'Account Blacklisted',
      body: 'Your account has been blacklisted. Please contact Jireta Loans for more information.',
      type: 'system',
      referenceId: blacklistEntry.id,
      sentBy: authResult.id,
    });

    return jsonResponse({ success: true, blacklist: blacklistEntry });
  } catch (err) {
    console.error('blacklist-add error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});