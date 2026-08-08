// supabase/functions/payments-record-office/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { getLoanFinancials, getSchedulePayment } from '../_shared/loan_financials.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
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
  } catch (err) {
    console.error('payments-record-office error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});