// supabase/functions/notifications-view/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   notifications-get-list   →  ?fn=get-list
//   notifications-mark-read  →  ?fn=mark-read
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { getAdminClient } from '../_shared/db.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'get-list';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'get-list':
        // ── [moved from functions/notifications-get-list/index.ts] ──────
        return await handleGetList(req);
      case 'mark-read':
        // ── [moved from functions/notifications-mark-read/index.ts] ─────
        return await handleMarkRead(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('notifications-view error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/notifications-get-list/index.ts] ──────────────────
async function handleGetList(req: Request) {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;

    const db = getAdminClient();
    const url = new URL(req.url);
    const page = parseInt(url.searchParams.get('page') ?? '1');
    const limit = parseInt(url.searchParams.get('limit') ?? '20');
    const isRead = url.searchParams.get('is_read');
    const type = url.searchParams.get('type');
    const offset = (page - 1) * limit;

    let query = db
      .from('notifications')
      .select('*', { count: 'exact' })
      .eq('user_id', authResult.id)
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (isRead !== null && isRead !== '') query = query.eq('is_read', isRead === 'true');
    if (type) query = query.eq('type', type);

    const { data, error, count } = await query;
    if (error) return errorResponse('Failed to fetch notifications', 500, 'DB_ERROR');

    const { count: unreadCount } = await db
      .from('notifications')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', authResult.id)
      .eq('is_read', false);

    return jsonResponse({
      data,
      unread_count: unreadCount ?? 0,
      meta: {
        page,
        limit,
        total: count ?? 0,
        total_pages: Math.ceil((count ?? 0) / limit),
      },
    });
  } catch (err) {
    console.error('notifications-get-list error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
}

// ── [moved from functions/notifications-mark-read/index.ts] ─────────────────
async function handleMarkRead(req: Request) {
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
}