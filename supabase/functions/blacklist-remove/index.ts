// supabase/functions/blacklist-remove/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { validateUUID } from '../_shared/validators.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const body = await req.json().catch(() => ({}));
    const { lender_id } = body;

    if (!lender_id || !validateUUID(lender_id)) {
      return errorResponse('Valid lender_id is required', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();

    const { data: active } = await db
      .from('blacklist')
      .select('id')
      .eq('lender_id', lender_id)
      .eq('is_active', true)
      .single();

    if (!active) {
      return errorResponse('No active blacklist entry found for this lender', 404, 'NOT_FOUND');
    }

    await db
      .from('blacklist')
      .update({ is_active: false, removed_by: authResult.id, removed_at: new Date().toISOString() })
      .eq('id', active.id);

    await db
      .from('lender_profiles')
      .update({ is_blacklisted: false })
      .eq('id', lender_id);

    await writeAuditLog({
      performedBy: authResult.id,
      action: 'blacklist_remove',
      tableName: 'blacklist',
      recordId: active.id,
      newValues: { lender_id, is_active: false },
    });

    await sendPushNotification({
      userId: lender_id,
      title: 'Account Reinstated',
      body: 'Your account blacklist has been removed. You may now apply for loans.',
      type: 'system',
      referenceId: active.id,
      sentBy: authResult.id,
    });

    return jsonResponse({ success: true });
  } catch (err) {
    console.error('blacklist-remove error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});