// supabase/functions/disbursements-view/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   disbursements-get-list  →  ?fn=get-list
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination } from '../_shared/validators.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'get-list';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'get-list':
        // ── [moved from functions/disbursements-get-list/index.ts] ──────
        return await handleGetList(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('disbursements-view error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/disbursements-get-list/index.ts] ───────────────────
async function handleGetList(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;

  const url = new URL(req.url);
  const { page, limit } = validatePagination(
    url.searchParams.get('page'),
    url.searchParams.get('limit'),
  );
  const status = url.searchParams.get('status');
  const method = url.searchParams.get('method');
  const disbursementId = url.searchParams.get('disbursement_id');
  const offset = (page - 1) * limit;

  const db = getAdminClient();
  let query = db.from('disbursements').select(
    `id, loan_id, method, amount, status,
     xendit_disbursement_id:xendit_id, xendit_reference, xendit_status,
     rider_id, disbursed_by:authorized_by, disbursed_at, delivery_date,
     notes:delivery_notes, delivery_proof, borrower_signature, created_at, updated_at,
     loan:loans!disbursements_loan_id_fkey(
       id, loan_number, status,
       lender_profiles!loans_lender_id_fkey(
         id, gcash_number,
         users!lender_profiles_id_fkey(id, first_name, last_name, phone_number)
       )
     ),
     rider:rider_profiles(id, plate_number, vehicle_type, users!rider_profiles_id_fkey(first_name, last_name))`,
    { count: 'exact' },
  );

  if (user.role === ROLES.LENDER) {
    query = query.eq('loans.lender_id', user.id);
  } else if (user.role === ROLES.RIDER) {
    query = query.eq('rider_id', user.id);
  }

  if (disbursementId) query = query.eq('id', disbursementId);
  if (status) query = query.eq('status', status);
  if (method) query = query.eq('method', method);

  query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);

  const { data, error, count } = await query;
  if (error) return errorResponse('Failed to fetch disbursements', 500, 'SERVER_ERROR');

  const mapped = (data ?? []).map((r: any) => ({
    ...r,
    lender_name: r.loan?.lender_profiles?.users
      ? `${r.loan.lender_profiles.users.first_name} ${r.loan.lender_profiles.users.last_name}`.trim()
      : null,
    loan_number: r.loan?.loan_number ?? null,
  }));

  return jsonResponse({
    data: mapped,
    total: count ?? 0,
    page,
    limit,
    totalPages: Math.ceil((count ?? 0) / limit),
  });
}