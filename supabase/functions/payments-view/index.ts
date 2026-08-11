// supabase/functions/payments-view/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   payments-get-list     →  ?fn=get-list
//   payments-get-receipt  →  ?fn=get-receipt
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
        // ── [moved from functions/payments-get-list/index.ts] ───────────
        return await handleGetList(req);
      case 'get-receipt':
        // ── [moved from functions/payments-get-receipt/index.ts] ────────
        return await handleGetReceipt(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('payments-view error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/payments-get-list/index.ts] ────────────────────────
async function handleGetList(req: Request) {
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
    .select(`id, loan_schedule_id, amount, payment_method, status, created_at, paid_at, notes, receipt_path, recorded_by,
      loan_schedules!inner(id, loan_id, loans!inner(id, loan_number, lender_id, lender_profiles!loans_lender_id_fkey(id, users!lender_profiles_id_fkey(first_name, last_name))))`, { count: 'exact' });
  if (user.role === ROLES.LENDER) query = query.eq('loan_schedules.loans.lender_id', user.id);
  if (status) query = query.eq('status', status);
  if (method) query = query.eq('payment_method', method);
  if (dateFrom) query = query.gte('created_at', dateFrom);
  if (dateTo) query = query.lte('created_at', dateTo);
  query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);
  const { data, error, count } = await query;
  if (error) return errorResponse('Failed to fetch payments', 500, 'SERVER_ERROR');
  const mapped = (data ?? []).map((p: any) => {
    const schedule = p.loan_schedules ?? null;
    const loan = schedule?.loans ?? null;
    const lender = loan?.lender_profiles?.users ?? null;
    return {
      id: p.id,
      loan_id: schedule?.loan_id ?? null,
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
}

// ── [moved from functions/payments-get-receipt/index.ts] ─────────────────────
async function handleGetReceipt(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const url = new URL(req.url);
  const paymentId = url.searchParams.get('payment_id');
  if (!paymentId) return errorResponse('payment_id required', 400, 'VALIDATION_ERROR');
  const db = getAdminClient();
  const { data: payment } = await db.from('payments').select('id, status, receipt_path, loan_schedules(loan_id, loans(lender_id))').eq('id', paymentId).single();
  if (!payment) return errorResponse('Payment not found', 404, 'NOT_FOUND');
  if (user.role === ROLES.LENDER && (payment as any).loan_schedules?.loans?.lender_id !== user.id) return errorResponse('Access denied', 403, 'FORBIDDEN');
  if (user.role === ROLES.RIDER) return errorResponse('Access denied', 403, 'FORBIDDEN');
  if (!(payment as any).receipt_path) return errorResponse('Receipt not yet generated', 404, 'NOT_FOUND');
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const { data: signedUrl } = await db.storage.from('receipts').createSignedUrl((payment as any).receipt_path, 3600);
  // createSignedUrl already returns an absolute URL; only prefix with the
  // storage base URL for bare relative paths so the URL never gets doubled.
  const signedPath = (signedUrl as any)?.signedUrl ?? null;
  const fullUrl = signedPath
    ? (String(signedPath).startsWith('http')
        ? signedPath
        : `${supabaseUrl}/storage/v1${signedPath}`)
    : null;
  return jsonResponse({ signed_url: fullUrl, receipt_url: fullUrl, payment_id: paymentId });
}