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
    const templateKey = url.searchParams.get('template_key') ?? url.searchParams.get('type');
    const dateFrom = url.searchParams.get('date_from') ?? url.searchParams.get('start_date');
    const dateTo = url.searchParams.get('date_to') ?? url.searchParams.get('end_date');
    const offset = (page - 1) * limit;

    let query = db
      .from('reports')
      .select(
        `id, report_type, title, parameters, file_path_pdf, file_path_excel,
         generated_by, generated_at, created_at,
         generated_by_user:users!reports_generated_by_fkey(id, first_name, last_name)`,
        { count: 'exact' }
      )
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (templateKey) query = query.eq('report_type', templateKey);
    if (dateFrom) query = query.gte('created_at', dateFrom);
    if (dateTo) query = query.lte('created_at', dateTo);

    const { data, error, count } = await query;
    if (error) return errorResponse('Failed to fetch report history', 500, 'DB_ERROR');

    const reports = (data ?? []).map((r: any) => ({
      id: r.id,
      template_key: r.report_type,
      template_name: r.title,
      format: r.file_path_pdf ? 'pdf' : r.file_path_excel ? 'xlsx' : 'pdf',
      file_url: r.file_path_pdf ?? r.file_path_excel ?? null,
      generated_by:
        r.generated_by_user
          ? `${r.generated_by_user.first_name} ${r.generated_by_user.last_name}`.trim()
          : r.generated_by,
      parameters: r.parameters,
      created_at: r.generated_at ?? r.created_at,
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