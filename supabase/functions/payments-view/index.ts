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
import { embedAsObject } from '../_shared/types.ts';

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
  const paymentId = url.searchParams.get('payment_id');
  const dateFrom = url.searchParams.get('date_from');
  const dateTo = url.searchParams.get('date_to');
  const offset = (page - 1) * limit;
  const db = getAdminClient();
  let query = db.from('payments')
    .select(`id, loan_schedule_id, payment_method, amount, status, xendit_payment_id, xendit_reference, idempotency_key, recorded_by, collection_assignment_id, receipt_path, notes, paid_at, created_at,
      loan_schedules!inner(id, loan_id, loans!inner(id, loan_number, lender_id, lender_profiles!loans_lender_id_fkey(id, users!lender_profiles_id_fkey(first_name, last_name)))),
      recorded_by_user:users!payments_recorded_by_fkey(id, first_name, last_name),
      reversal:payment_reversals(id, reason, reversed_by, reversed_at, reversed_by_user:users!payment_reversals_reversed_by_fkey(id, first_name, last_name))`, { count: 'exact' });
  if (user.role === ROLES.LENDER) query = query.eq('loan_schedules.loans.lender_id', user.id);
  if (paymentId) query = query.eq('id', paymentId);
  if (status) query = query.eq('status', status);
  if (method) query = query.eq('payment_method', method);
  if (dateFrom) query = query.gte('created_at', dateFrom);
  if (dateTo) query = query.lte('created_at', dateTo);
  query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);
  const { data, error, count } = await query;
  if (error) return errorResponse('Failed to fetch payments', 500, 'SERVER_ERROR');
  const mapped = (data ?? []).map((p) => {
    const schedule = embedAsObject(p.loan_schedules);
    const loanEmbed = schedule ? embedAsObject(schedule.loans) : null;
    const lp = loanEmbed ? embedAsObject(loanEmbed.lender_profiles) : null;
    const lender = lp ? embedAsObject(lp.users) : null;
    const recordedByUser = embedAsObject(p.recorded_by_user);
    const reversal = Array.isArray(p.reversal)
      ? (p.reversal[0] ?? null)
      : (embedAsObject(p.reversal) ?? null);
    const reversalUser = reversal ? embedAsObject(reversal.reversed_by_user) : null;
    return {
      id: p.id,
      loan_id: schedule?.loan_id ?? null,
      loan_schedule_id: p.loan_schedule_id,
      amount: p.amount,
      method: p.payment_method,
      payment_method: p.payment_method,
      status: p.status,
      recorded_by: p.recorded_by,
      recorded_by_user: recordedByUser ?? null,
      recorded_by_name: recordedByUser
        ? `${recordedByUser.first_name ?? ''} ${recordedByUser.last_name ?? ''}`.trim()
        : null,
      notes: p.notes,
      receipt_url: p.receipt_path,
      xendit_payment_id: p.xendit_payment_id,
      xendit_reference: p.xendit_reference,
      reference_number: p.xendit_reference ?? p.xendit_payment_id ?? null,
      idempotency_key: p.idempotency_key,
      collection_assignment_id: p.collection_assignment_id,
      created_at: p.created_at,
      paid_at: p.paid_at,
      loan: loanEmbed
        ? { ...loanEmbed, lender, loan_number: loanEmbed.loan_number }
        : null,
      // Flat convenience fields so every consumer (employee/HM/lender screens)
      // can render correctly regardless of which nested keys it reads.
      lender,
      lender_name: [lender?.first_name, lender?.last_name].filter(Boolean).join(' ') || null,
      loan_number: loanEmbed?.loan_number ?? null,
      // Reversal details (from payment_reversals) so the details screens can
      // show who/when/why a payment was reversed.
      reversed_at: reversal?.reversed_at ?? null,
      reversed_by: reversal?.reversed_by ?? null,
      reversed_by_name: reversalUser
        ? `${reversalUser.first_name ?? ''} ${reversalUser.last_name ?? ''}`.trim()
        : null,
      reversal_reason: reversal?.reason ?? null,
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
  const paymentLenderId = embedAsObject(embedAsObject(payment?.loan_schedules)?.loans)?.lender_id;
  if (user.role === ROLES.LENDER && paymentLenderId !== user.id) return errorResponse('Access denied', 403, 'FORBIDDEN');
  if (user.role === ROLES.RIDER) return errorResponse('Access denied', 403, 'FORBIDDEN');
  if (!payment?.receipt_path) return errorResponse('Receipt not yet generated', 404, 'NOT_FOUND');
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const { data: signedUrl } = await db.storage.from('receipts').createSignedUrl(payment?.receipt_path, 3600);
  // createSignedUrl already returns an absolute URL; only prefix with the
  // storage base URL for bare relative paths so the URL never gets doubled.
  const signedPath = signedUrl?.signedUrl ?? null;
  const fullUrl = signedPath
    ? (String(signedPath).startsWith('http')
        ? signedPath
        : `${supabaseUrl}/storage/v1${signedPath}`)
    : null;
  return jsonResponse({ signed_url: fullUrl, receipt_url: fullUrl, payment_id: paymentId });
}