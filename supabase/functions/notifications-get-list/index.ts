// supabase/functions/notifications-get-list/index.ts
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
});