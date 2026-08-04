
// supabase/functions/collections-get-list/index.ts
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
    const riderId = url.searchParams.get('rider_id');
    const offset = (page - 1) * limit;
    const db = getAdminClient();
    let query = db.from('collection_assignments')
      .select(`id, status, rider_id, assigned_by, amount_collected, collection_schedule, response_at, completed_at, created_at,
        notes:collection_notes,
        proof_photo, borrower_signature, collection_photo,
        loans(id, loan_number, outstanding_balance, lender_profiles!loans_lender_id_fkey(id, users!lender_profiles_id_fkey(first_name, last_name, phone_number))),
        loan_schedule:loan_schedules(installment_number, due_date, amount_due),
        rider:rider_profiles(id, users!rider_profiles_id_fkey(first_name, last_name)),
        assigned_by_user:users!collection_assignments_assigned_by_fkey(id, first_name, last_name)`, { count: 'exact' });
    if (user.role === ROLES.RIDER) query = query.eq('rider_id', user.id);
    else if (user.role === ROLES.LENDER) query = query.eq('loans.lender_id', user.id);
    else if (riderId) query = query.eq('rider_id', riderId);
    if (status) query = query.eq('status', status);
    query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);
    const { data, error, count } = await query;
    if (error) return errorResponse('Failed to fetch collections', 500, 'SERVER_ERROR');
    return jsonResponse({ data: data ?? [], total: count ?? 0, page, limit, totalPages: Math.ceil((count ?? 0) / limit) });
  } catch (err) {
    console.error('collections-get-list error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});