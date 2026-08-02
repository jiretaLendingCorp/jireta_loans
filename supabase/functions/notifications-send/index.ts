// supabase/functions/notifications-send/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { writeAuditLog } from '../_shared/audit.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const body = await req.json();
    const { user_id, title, message, type, reference_id } = body;

    if (!user_id || !title || !message || !type) {
      return errorResponse('user_id, title, message, and type are required', 400, 'MISSING_FIELDS');
    }

    const db = getAdminClient();

    const { data: targetUser, error: userErr } = await db
      .from('users')
      .select('id, fcm_token, account_status')
      .eq('id', user_id)
      .single();

    if (userErr || !targetUser) return errorResponse('Target user not found', 404, 'NOT_FOUND');
    if (targetUser.account_status !== 'active') {
      return errorResponse('Cannot send notification to inactive user', 422, 'USER_INACTIVE');
    }

    const { data: notification, error: notifErr } = await db
      .from('notifications')
      .insert({
        user_id,
        title,
        message,
        type,
        reference_id: reference_id ?? null,
        sent_by: authResult.id,
        is_read: false,
      })
      .select()
      .single();

    if (notifErr) return errorResponse('Failed to create notification', 500, 'DB_ERROR');

    if (targetUser.fcm_token) {
      await sendPushNotification(targetUser.fcm_token, title, message, {
        type,
        reference_id: reference_id ?? '',
        notification_id: notification.id,
      });
    }

    await writeAuditLog({
      performedBy: authResult.id,
      action: 'notification_sent',
      tableName: 'notifications',
      recordId: notification.id,
      newValues: { user_id, title, type },
    });

    return jsonResponse({ success: true, notification_id: notification.id });
  } catch (err) {
    console.error('notifications-send error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});