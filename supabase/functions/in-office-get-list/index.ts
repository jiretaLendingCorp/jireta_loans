// supabase/functions/in-office-get-list/index.ts
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
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const db = getAdminClient();
    const url = new URL(req.url);
    const page = parseInt(url.searchParams.get('page') ?? '1');
    const limit = parseInt(url.searchParams.get('limit') ?? '20');
    const status = url.searchParams.get('status');
    const dateFrom = url.searchParams.get('date_from');
    const dateTo = url.searchParams.get('date_to');
    const offset = (page - 1) * limit;

    let query = db
      .from('in_office_applications')
      .select(
        `id, status, wizard_step, created_at, submitted_at, updated_at,
         loan_id,
         personal_info:application_personal_info!application_personal_info_application_id_fkey(
           first_name, last_name, phone_number
         ),
         created_by_user:users!in_office_applications_created_by_fkey(
           id, first_name, last_name, roles(name)
         ),
         loan:loans!in_office_applications_loan_id_fkey(id, loan_number, principal_amount, status)`,
        { count: 'exact' }
      )
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (authResult.role === ROLES.EMPLOYEE) {
      query = query.eq('created_by', authResult.id);
    }
    if (status) query = query.eq('status', status);
    if (dateFrom) query = query.gte('created_at', dateFrom);
    if (dateTo) query = query.lte('created_at', dateTo);

    const { data, error, count } = await query;
    if (error) return errorResponse('Failed to fetch in-office applications', 500, 'DB_ERROR');

    const rows = (data ?? []).map((row: any) => {
      const pi = row.personal_info ?? null;
      return {
        ...row,
        lender_name: pi ? `${pi.first_name ?? ''} ${pi.last_name ?? ''}`.trim() : null,
      };
    });

    return jsonResponse({
      data: rows,
      meta: {
        page,
        limit,
        total: count ?? 0,
        total_pages: Math.ceil((count ?? 0) / limit),
      },
    });
  } catch (err) {
    console.error('in-office-get-list error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});