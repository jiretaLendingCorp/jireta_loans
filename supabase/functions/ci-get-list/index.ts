
// supabase/functions/ci-get-list/index.ts
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
    if (user.role === ROLES.LENDER) return errorResponse('Access denied', 403, 'FORBIDDEN');
    const url = new URL(req.url);
    const { page, limit } = validatePagination(url.searchParams.get('page'), url.searchParams.get('limit'));
    const status = url.searchParams.get('status');
    const riderId = url.searchParams.get('rider_id');
    const offset = (page - 1) * limit;
    const db = getAdminClient();
    let query = db.from('credit_investigations')
      .select(`id, status, investigation_notes, deadline, created_at, completed_at, report_summary,
        loans(id, loan_number, users(first_name, last_name, phone)),
        rider:users!rider_id(id, first_name, last_name),
        assigner:users!assigned_by(id, first_name, last_name)`, { count: 'exact' });
    if (user.role === ROLES.RIDER) query = query.eq('rider_id', user.id);
    else if (riderId) query = query.eq('rider_id', riderId);
    if (status) query = query.eq('status', status);
    query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);
    const { data, error, count } = await query;
    if (error) return errorResponse('Failed to fetch CI list', 500, 'SERVER_ERROR');
    return jsonResponse({ data: data ?? [], total: count ?? 0, page, limit, totalPages: Math.ceil((count ?? 0) / limit) });
  } catch (err) {
    console.error('ci-get-list error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});