// supabase/functions/payments-xendit-link/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   payments-generate-xendit-link  →  ?fn=generate
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { createInvoice } from '../_shared/xendit.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { getSchedulePayment, scheduleStatus } from '../_shared/loan_financials.ts';
import { guardRateLimit } from '../_shared/rate_limiter.ts';

// Abuse detection: at most 3 payment-link attempts per lender per loan
// schedule per 15 minutes. Repeated attempts beyond that are treated as
// suspicious activity and temporarily blocked for review.
const PAYMENT_ATTEMPT_MAX = 3;
const PAYMENT_ATTEMPT_WINDOW_MINUTES = 15;
const PAYMENT_BLOCK_MINUTES = 30;

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'generate';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'generate':
        // ── [moved from functions/payments-generate-xendit-link/index.ts] ─
        return await handleGenerate(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('payments-xendit-link error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/payments-generate-xendit-link/index.ts] ────────────
async function handleGenerate(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const roleCheck = requireRole(user, ROLES.LENDER);
  if (roleCheck) return roleCheck;
  const { loan_id, loan_schedule_id } = await req.json();
  if (!loan_id || !loan_schedule_id) return errorResponse('loan_id and loan_schedule_id required', 400, 'VALIDATION_ERROR');
  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown';

  // Abuse detection: 3 payment-link attempts per schedule → temporary block
  // for review. Prevents a lender (or attacker) from repeatedly generating
  // invoices on the same installment in a short window.
  const attemptKey = `payment:${user.id}:${loan_schedule_id}`;
  const attemptGuard = await guardRateLimit({
    key: attemptKey,
    maxAttempts: PAYMENT_ATTEMPT_MAX,
    windowMinutes: PAYMENT_ATTEMPT_WINDOW_MINUTES,
    blockMinutes: PAYMENT_BLOCK_MINUTES,
    blockReason: 'Multiple payment attempts on same installment',
    eventType: 'payment_attempt_blocked',
    userId: user.id,
    ipAddress: ip,
  });
  if (!attemptGuard.allowed) {
    try {
      await db.from('auth_logs').insert({
        user_id: user.id,
        event_type: 'payment_attempt_blocked',
        ip_address: ip,
      });
    } catch (_) {}
    const waitMinutes = attemptGuard.block?.retryAfterSeconds
      ? Math.ceil(attemptGuard.block.retryAfterSeconds / 60)
      : PAYMENT_BLOCK_MINUTES;
    return errorResponse(
      `Too many payment attempts for this installment. Try again in ${waitMinutes} minute(s).`,
      429,
      'PAYMENT_ATTEMPT_BLOCKED',
    );
  }

  const { data: loan } = await db.from('loans').select('id, loan_number, lender_id, status').eq('id', loan_id).eq('lender_id', user.id).single();
  if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
  if (loan.status !== 'active') return errorResponse('Loan is not active', 400, 'INVALID_STATUS');
  const { data: schedule } = await db.from('loan_schedules').select('id, amount_due, due_date').eq('id', loan_schedule_id).eq('loan_id', loan_id).single();
  if (!schedule) return errorResponse('Schedule not found', 404, 'NOT_FOUND');
  const schedulePayment = await getSchedulePayment(db, loan_schedule_id);
  if (scheduleStatus(schedulePayment.amount_paid, schedule.amount_due, schedule.due_date) === 'paid') return errorResponse('Installment already paid', 400, 'PAYMENT_ALREADY_MADE');
  const { data: userInfo } = await db.from('users').select('email, first_name, last_name').eq('id', user.id).single();
  const externalId = `${loan.loan_number}-SCHED-${loan_schedule_id}-${Date.now()}`;
  const invoice = await createInvoice({ externalId, amount: schedule.amount_due, payerEmail: userInfo?.email ?? undefined, description: `Payment for ${loan.loan_number} installment due ${schedule.due_date}` });
  const { data: payment } = await db.from('payments').insert({ loan_schedule_id, amount: schedule.amount_due, payment_method: 'gcash_xendit', status: 'pending', xendit_payment_id: invoice.id, xendit_reference: externalId }).select('id').single();
  if (!payment) return errorResponse('Failed to create payment record', 500, 'DB_ERROR');
  await db.from('xendit_logs').insert({ loan_id, payment_id: payment.id, event_type: 'payment', xendit_id: invoice.id, payload: invoice, status: 'created' });
  await writeAuditLog({ performedBy: user.id, action: 'generate_gcash_link', tableName: 'payments', recordId: payment.id, ipAddress: ip });
  return jsonResponse({ invoice_url: invoice.invoiceUrl, xendit_invoice_id: invoice.id, payment_id: payment.id });
}