
// supabase/functions/kyc-get-list/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination } from '../_shared/validators.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const url = new URL(req.url);
    const { page, limit } = validatePagination(url.searchParams.get('page'), url.searchParams.get('limit'));
    const status = url.searchParams.get('status');
    const search = url.searchParams.get('search');
    const offset = (page - 1) * limit;

    const db = getAdminClient();
    let query = db.from('lender_profiles')
      .select(`kyc_status, user_id, users!inner(id, first_name, last_name, phone, account_status), 
        kyc_documents(id, document_type, status, created_at)`, { count: 'exact' })
      .neq('kyc_status', 'not_submitted');

    if (status) query = query.eq('kyc_status', status);
    if (search) query = query.or(`users.first_name.ilike.%${search}%,users.last_name.ilike.%${search}%`);

    query = query.order('created_at', { ascending: false, foreignTable: 'kyc_documents' }).range(offset, offset + limit - 1);

    const { data, error, count } = await query;
    if (error) return errorResponse('Failed to fetch KYC list', 500, 'SERVER_ERROR');

    return jsonResponse({ data: data ?? [], total: count ?? 0, page, limit, totalPages: Math.ceil((count ?? 0) / limit) });
  } catch (err) {
    console.error('kyc-get-list error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});