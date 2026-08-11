// supabase/functions/collections-view/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes actions through ONE deployable function using
// the `?fn=<action>` query parameter.
//
//   collections-get-list  →  ?fn=get-list
//
// The original action logic is preserved verbatim below.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination } from '../_shared/validators.ts';
import { getLoanFinancialsBatch } from '../_shared/loan_financials.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'get-list';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'get-list':
        // ── [moved from functions/collections-get-list/index.ts] ─────────
        return await handleCollectionGetList(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('collections-view error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/collections-get-list/index.ts] ────────────────────
async function handleCollectionGetList(req: Request) {
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
      loan_schedule:loan_schedules(installment_number, due_date, amount_due, loan:loans(id, loan_number, lender_profiles!loans_lender_id_fkey(id, users!lender_profiles_id_fkey(first_name, last_name, phone_number)))),
      rider:rider_profiles(id, users!rider_profiles_id_fkey(first_name, last_name)),
      assigned_by_user:users!collection_assignments_assigned_by_fkey(id, first_name, last_name)`, { count: 'exact' });
  if (user.role === ROLES.RIDER) query = query.eq('rider_id', user.id);
  else if (user.role === ROLES.LENDER) query = query.eq('loan_schedule.loan.lender_id', user.id);
  else if (riderId) query = query.eq('rider_id', riderId);
  if (status) query = query.eq('status', status);
  query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);
  const { data, error, count } = await query;
  if (error) return errorResponse('Failed to fetch collections', 500, 'SERVER_ERROR');

  const loanIds = (data ?? []).map((r: any) => r.loan_schedule?.loan?.id).filter(Boolean);
  const financials = await getLoanFinancialsBatch(db, loanIds);
  const mapped = (data ?? []).map((r: any) => {
    const schedule = r.loan_schedule ?? null;
    const loan = schedule?.loan
      ? { ...schedule.loan, outstanding_balance: financials[schedule.loan.id]?.outstanding_balance ?? null }
      : null;
    return {
      ...r,
      loans: loan,
      loan_schedule: schedule
        ? { installment_number: schedule.installment_number, due_date: schedule.due_date, amount_due: schedule.amount_due }
        : null,
    };
  });
  return jsonResponse({ data: mapped, total: count ?? 0, page, limit, totalPages: Math.ceil((count ?? 0) / limit) });
}