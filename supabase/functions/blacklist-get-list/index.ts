// supabase/functions/blacklist-get-list/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const db = getAdminClient();
    const url = new URL(req.url);
    const page = parseInt(url.searchParams.get('page') ?? '1');
    const limit = parseInt(url.searchParams.get('limit') ?? '20');
    const search = url.searchParams.get('search') ?? '';
    const isActive = url.searchParams.get('is_active');
    const dateFrom = url.searchParams.get('date_from');
    const dateTo = url.searchParams.get('date_to');
    const offset = (page - 1) * limit;

    let query = db
      .from('blacklist')
      .select(
        `id, reason, is_active, created_at, removed_at,
         lender:users!blacklist_lender_id_fkey(
           id, first_name, last_name, phone_number,
           lender_profiles(gcash_number, kyc_status)
         ),
         added_by_user:users!blacklist_added_by_fkey(id, first_name, last_name),
         removed_by_user:users!blacklist_removed_by_fkey(id, first_name, last_name)`,
        { count: 'exact' }
      )
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (isActive !== null && isActive !== '') query = query.eq('is_active', isActive === 'true');
    if (dateFrom) query = query.gte('created_at', dateFrom);
    if (dateTo) query = query.lte('created_at', dateTo);

    const { data, error, count } = await query;
    if (error) return errorResponse('Failed to fetch blacklist', 500, 'DB_ERROR');

    let filtered = data ?? [];
    if (search) {
      const s = search.toLowerCase();
      filtered = filtered.filter((b: any) => {
        const name = `${b.lender?.first_name} ${b.lender?.last_name}`.toLowerCase();
        return name.includes(s) || b.lender?.phone_number?.includes(s);
      });
    }

    return jsonResponse({
      data: filtered,
      meta: {
        page,
        limit,
        total: count ?? 0,
        total_pages: Math.ceil((count ?? 0) / limit),
      },
    });
  } catch (err) {
    console.error('blacklist-get-list error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});