// supabase/functions/ci-view/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes actions through ONE deployable function using
// the `?fn=<action>` query parameter.
//
//   ci-get-list  →  ?fn=get-list
//
// The original action logic is preserved verbatim below.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination } from '../_shared/validators.ts';
import { getLenderAddressBatch } from '../_shared/loan_financials.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'get-list';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'get-list':
        // ── [moved from functions/ci-get-list/index.ts] ──────────────────
        return await handleCiGetList(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('ci-view error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/ci-get-list/index.ts] ─────────────────────────────
async function handleCiGetList(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  if (user.role === ROLES.LENDER) return errorResponse('Access denied', 403, 'FORBIDDEN');
  const url = new URL(req.url);
  const { page, limit } = validatePagination(url.searchParams.get('page'), url.searchParams.get('limit'));
  const status = url.searchParams.get('status');
  const riderId = url.searchParams.get('rider_id');
  const ciId = url.searchParams.get('ci_id');
  const offset = (page - 1) * limit;
  const db = getAdminClient();
  let query = db.from('credit_investigations')
    .select(`id, status, investigation_notes, deadline, created_at, completed_at, report_summary,
      loan_id,
      loans(id, loan_number, lender_id, lender_profiles!loans_lender_id_fkey(id, users!lender_profiles_id_fkey(id, first_name, middle_name, last_name, phone_number))),
      rider:rider_profiles(users!rider_profiles_id_fkey(id, first_name, last_name)),
      assigner:users(id, first_name, last_name)`, { count: 'exact' });
  if (user.role === ROLES.RIDER) query = query.eq('rider_id', user.id);
  else if (riderId) query = query.eq('rider_id', riderId);
  if (ciId) query = query.eq('id', ciId);
  if (status) query = query.eq('status', status);
  query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);
  const { data, error, count } = await query;
  if (error) return errorResponse('Failed to fetch CI list', 500, 'SERVER_ERROR');

  const lenderIds = (data ?? [])
    .map((r: any) => r.loans?.lender_id ?? r.loans?.[0]?.lender_id)
    .filter(Boolean);
  const lenderAddresses = await getLenderAddressBatch(db, lenderIds);

  const rows = (data ?? []).map((r: any) => {
    const loan = r.loans ?? null;
    const lp = loan?.lender_profiles ?? null;
    const users = lp?.users ?? null;
    const lenderId = loan?.lender_id ?? null;
    return {
      ...r,
      loans: loan
        ? {
            ...loan,
            lender_name: users
              ? `${users.first_name ?? ''} ${users.last_name ?? ''}`.trim()
              : null,
            lender_profile: lp,
            lender_address: lenderId ? (lenderAddresses[lenderId] ?? null) : null,
          }
        : null,
    };
  });

  return jsonResponse({ data: rows, total: count ?? 0, page, limit, totalPages: Math.ceil((count ?? 0) / limit) });
}