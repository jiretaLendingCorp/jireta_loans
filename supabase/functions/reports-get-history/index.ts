// supabase/functions/reports-get-history/index.ts
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
    const templateKey = url.searchParams.get('template_key');
    const dateFrom = url.searchParams.get('date_from');
    const dateTo = url.searchParams.get('date_to');
    const offset = (page - 1) * limit;

    let query = db
      .from('reports')
      .select(
        `id, template_key, template_name, parameters, row_count, status,
         created_at, storage_path,
         generated_by_user:users!reports_generated_by_fkey(id, first_name, last_name)`,
        { count: 'exact' }
      )
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (templateKey) query = query.eq('template_key', templateKey);
    if (dateFrom) query = query.gte('created_at', dateFrom);
    if (dateTo) query = query.lte('created_at', dateTo);

    const { data, error, count } = await query;
    if (error) return errorResponse('Failed to fetch report history', 500, 'DB_ERROR');

    const reports = (data ?? []).map((r: any) => ({
      ...r,
      data_snapshot: undefined,
    }));

    return jsonResponse({
      data: reports,
      meta: {
        page,
        limit,
        total: count ?? 0,
        total_pages: Math.ceil((count ?? 0) / limit),
      },
    });
  } catch (err) {
    console.error('reports-get-history error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});