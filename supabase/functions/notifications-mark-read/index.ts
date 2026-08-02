// supabase/functions/notifications-mark-read/index.ts
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

    const body = await req.json();
    const { notification_id, mark_all } = body;

    const db = getAdminClient();

    if (mark_all === true) {
      const { error } = await db
        .from('notifications')
        .update({ is_read: true, read_at: new Date().toISOString() })
        .eq('user_id', authResult.id)
        .eq('is_read', false);

      if (error) return errorResponse('Failed to mark notifications as read', 500, 'DB_ERROR');
      return jsonResponse({ success: true, message: 'All notifications marked as read' });
    }

    if (!notification_id) {
      return errorResponse('notification_id or mark_all required', 400, 'MISSING_FIELDS');
    }

    const { data: notification } = await db
      .from('notifications')
      .select('id, user_id')
      .eq('id', notification_id)
      .single();

    if (!notification) return errorResponse('Notification not found', 404, 'NOT_FOUND');
    if (notification.user_id !== authResult.id) {
      return errorResponse('Access denied', 403, 'FORBIDDEN');
    }

    const { error } = await db
      .from('notifications')
      .update({ is_read: true, read_at: new Date().toISOString() })
      .eq('id', notification_id);

    if (error) return errorResponse('Failed to mark notification as read', 500, 'DB_ERROR');
    return jsonResponse({ success: true, notification_id });
  } catch (err) {
    console.error('notifications-mark-read error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});