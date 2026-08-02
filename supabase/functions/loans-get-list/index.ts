// supabase/functions/loans-get-list/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination } from '../_shared/validators.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const url = new URL(req.url);
    const { page, limit } = validatePagination(url.searchParams.get('page'), url.searchParams.get('limit'));
    const status = url.searchParams.get('status');
    const search = url.searchParams.get('search');
    const dateFrom = url.searchParams.get('date_from');
    const dateTo = url.searchParams.get('date_to');
    const offset = (page - 1) * limit;

    const db = getAdminClient();
    let query = db.from('loans')
      .select(`id, loan_number, principal, total_payable, outstanding_balance, interest_rate,
        frequency, term_days, status, created_at, approved_at, disbursed_at, completed_at,
        users!inner(id, first_name, last_name, phone)`, { count: 'exact' });

    if (user.role === ROLES.LENDER) {
      query = query.eq('user_id', user.id);
    } else if (user.role === ROLES.EMPLOYEE) {
      query = query.eq('processed_by', user.id);
    } else if (user.role === ROLES.RIDER) {
      return errorResponse('Access denied', 403, 'FORBIDDEN');
    }

    if (status) query = query.eq('status', status);
    if (search) query = query.or(`loan_number.ilike.%${search}%,users.first_name.ilike.%${search}%,users.last_name.ilike.%${search}%`);
    if (dateFrom) query = query.gte('created_at', dateFrom);
    if (dateTo) query = query.lte('created_at', dateTo);

    query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);

    const { data, error, count } = await query;
    if (error) return errorResponse('Failed to fetch loans', 500, 'SERVER_ERROR');

    return jsonResponse({ data: data ?? [], total: count ?? 0, page, limit, totalPages: Math.ceil((count ?? 0) / limit) });
  } catch (err) {
    console.error('loans-get-list error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
