// supabase/functions/payments-get-list/index.ts
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
    if (user.role === ROLES.RIDER) return errorResponse('Access denied', 403, 'FORBIDDEN');
    const url = new URL(req.url);
    const { page, limit } = validatePagination(url.searchParams.get('page'), url.searchParams.get('limit'));
    const status = url.searchParams.get('status');
    const method = url.searchParams.get('method');
    const dateFrom = url.searchParams.get('date_from');
    const dateTo = url.searchParams.get('date_to');
    const offset = (page - 1) * limit;
    const db = getAdminClient();
    let query = db.from('payments')
      .select(`id, loan_id, loan_schedule_id, amount, payment_method, status, created_at, paid_at, notes, receipt_path, recorded_by,
        loans!inner(id, loan_number, lender_id, lender_profiles!loans_lender_id_fkey(id, users!lender_profiles_id_fkey(first_name, last_name)))`, { count: 'exact' });
    if (user.role === ROLES.LENDER) query = query.eq('loans.lender_id', user.id);
    if (status) query = query.eq('status', status);
    if (method) query = query.eq('payment_method', method);
    if (dateFrom) query = query.gte('created_at', dateFrom);
    if (dateTo) query = query.lte('created_at', dateTo);
    query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);
    const { data, error, count } = await query;
    if (error) return errorResponse('Failed to fetch payments', 500, 'SERVER_ERROR');
    const mapped = (data ?? []).map((p: any) => {
      const loan = p.loans ?? null;
      const lender = loan?.lender_profiles?.users ?? null;
      return {
        id: p.id,
        loan_id: p.loan_id,
        loan_schedule_id: p.loan_schedule_id,
        amount: p.amount,
        method: p.payment_method,
        status: p.status,
        recorded_by: p.recorded_by,
        notes: p.notes,
        receipt_url: p.receipt_path,
        created_at: p.created_at,
        paid_at: p.paid_at,
        loan: loan ? { ...loan, lender } : null,
      };
    });
    return jsonResponse({ data: mapped, total: count ?? 0, page, limit, totalPages: Math.ceil((count ?? 0) / limit) });
  } catch (err) {
    console.error('payments-get-list error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});