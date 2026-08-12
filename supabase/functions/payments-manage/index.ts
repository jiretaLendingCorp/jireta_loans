// supabase/functions/payments-manage/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   payments-record-office  →  ?fn=record-office
//   payments-reverse        →  ?fn=reverse
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeString } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { getPaymentLoanId, getLoanFinancials, getSchedulePayment } from '../_shared/loan_financials.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'record-office';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'record-office':
        // ── [moved from functions/payments-record-office/index.ts] ──────
        return await handleRecordOffice(req);
      case 'reverse':
        // ── [moved from functions/payments-reverse/index.ts] ────────────
        return await handleReverse(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('payments-manage error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/payments-record-office/index.ts] ───────────────────
async function handleRecordOffice(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const idempotencyKey = req.headers.get('x-idempotency-key');
  if (!idempotencyKey) return errorResponse('Idempotency key required', 400, 'VALIDATION_ERROR');

  const { loan_id, loan_schedule_id, amount, notes } = await req.json();

  if (!loan_id || !loan_schedule_id || !amount) {
    return errorResponse('loan_id, loan_schedule_id, and amount are required', 400, 'VALIDATION_ERROR');
  }
  if (Number(amount) <= 0) return errorResponse('Amount must be positive', 400, 'VALIDATION_ERROR');

  const db = getAdminClient();

  const { data: existing } = await db
    .from('payments')
    .select('id')
    .eq('idempotency_key', idempotencyKey)
    .single();

  if (existing) return errorResponse('Duplicate payment detected', 409, 'IDEMPOTENCY_CONFLICT');

  const { data: loan } = await db
    .from('loans')
    .select('id, lender_id, status')
    .eq('id', loan_id)
    .single();

  if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
  if (!['active', 'overdue'].includes(loan.status)) {
    return errorResponse('Loan is not in payable status', 409, 'INVALID_STATUS');
  }

  const financials = await getLoanFinancials(db, loan_id);
  if (!financials) return errorResponse('Loan not found', 404, 'NOT_FOUND');
  if (Number(amount) > financials.outstanding_balance) {
    return errorResponse('Amount exceeds outstanding balance', 400, 'VALIDATION_ERROR');
  }

  const { data: schedule } = await db
    .from('loan_schedules')
    .select('id, amount_due, due_date')
    .eq('id', loan_schedule_id)
    .single();

  if (!schedule) return errorResponse('Schedule not found', 404, 'NOT_FOUND');
  const schedulePayment = await getSchedulePayment(db, loan_schedule_id);
  if (schedulePayment.amount_paid >= Number(schedule.amount_due)) return errorResponse('Installment already paid', 409, 'PAYMENT_ALREADY_MADE');

  const { data: payment, error: payErr } = await db.from('payments').insert({
    loan_schedule_id,
    amount: Number(amount),
    payment_method: 'office_cash',
    status: 'verified',
    recorded_by: authResult.id,
    idempotency_key: idempotencyKey,
    notes: notes ?? null,
    paid_at: new Date().toISOString(),
  }).select().single();

  if (payErr || !payment) return errorResponse('Failed to record payment', 500, 'SERVER_ERROR');

  const newBalance = Math.max(0, Math.round((financials.outstanding_balance - Number(amount)) * 100) / 100);
  const loanStatus = newBalance <= 0 ? 'completed' : loan.status;

  await db.from('loans').update({
    status: loanStatus,
  }).eq('id', loan_id);

  await writeAuditLog({
    performedBy: authResult.id,
    action: 'payment_recorded',
    tableName: 'payments',
    recordId: payment.id,
    newValues: { amount: Number(amount), method: 'office_cash', loan_id },
    ipAddress: req.headers.get('x-forwarded-for') ?? undefined,
  });

  await sendPushNotification({
    userId: loan.lender_id,
    title: 'Payment Recorded',
    body: `Your payment of ₱${Number(amount).toLocaleString()} has been recorded. Remaining balance: ₱${newBalance.toLocaleString()}`,
    type: 'payment_recorded',
    referenceId: payment.id,
  });

  return jsonResponse({
    payment_id: payment.id,
    amount: Number(amount),
    outstanding_balance: newBalance,
    loan_status: loanStatus,
  }, 201);
}

// ── [moved from functions/payments-reverse/index.ts] ─────────────────────────
async function handleReverse(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const roleCheck = requireRole(user, ROLES.HEAD_MANAGER);
  if (roleCheck) return roleCheck;
  const { payment_id, reason } = await req.json();
  if (!payment_id || !reason) return errorResponse('payment_id and reason required', 400, 'VALIDATION_ERROR');
  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
  const { data: payment } = await db.from('payments').select('id, status, amount, loan_schedule_id, collection_assignment_id').eq('id', payment_id).single();
  if (!payment) return errorResponse('Payment not found', 404, 'NOT_FOUND');
  if (payment.status !== 'verified') return errorResponse('Only verified payments can be reversed', 400, 'INVALID_STATUS');
  await db.from('payments').update({ status: 'reversed' }).eq('id', payment_id);
  await db.from('payment_reversals').insert({ payment_id, reversed_by: user.id, reason: sanitizeString(reason) });
  const loanId = await getPaymentLoanId(db, payment);
  if (loanId) await db.from('loans').update({ status: 'active' }).eq('id', loanId);
  const lenderId = loanId
    ? (await db.from('loans').select('lender_id').eq('id', loanId).single()).data?.lender_id
    : null;
  await writeAuditLog({ performedBy: user.id, action: 'payment_reverse', tableName: 'payments', recordId: payment_id, oldValues: { status: 'verified', amount: payment.amount }, newValues: { status: 'reversed', reason }, ipAddress: ip });
  if (lenderId) {
    await sendPushNotification({ userId: lenderId, title: 'Payment Reversed', body: `A payment of ₱${Number(payment.amount).toLocaleString()} has been reversed.`, type: 'payment_reversed', referenceId: payment_id });
  }
  return jsonResponse({ message: 'Payment reversed, balance restored' });
}