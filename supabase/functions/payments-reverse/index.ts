
// supabase/functions/payments-reverse/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeString } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;
    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;
    const { payment_id, reason } = await req.json();
    if (!payment_id || !reason) return errorResponse('payment_id and reason required', 400, 'VALIDATION_ERROR');
    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
    const { data: payment } = await db.from('payments').select('id, status, amount, loan_id, loan_schedule_id, loans(user_id, outstanding_balance)').eq('id', payment_id).single();
    if (!payment) return errorResponse('Payment not found', 404, 'NOT_FOUND');
    if (payment.status !== 'verified') return errorResponse('Only verified payments can be reversed', 400, 'INVALID_STATUS');
    await db.from('payments').update({ status: 'reversed', reversed_by: user.id, reversed_at: new Date().toISOString(), reversal_reason: sanitizeString(reason) }).eq('id', payment_id);
    await db.from('loan_schedules').update({ status: 'pending', paid_at: null, amount_paid: null }).eq('id', payment.loan_schedule_id);
    const loanData = (payment as any).loans;
    const restoredBalance = Math.round((loanData.outstanding_balance + payment.amount) * 100) / 100;
    await db.from('loans').update({ outstanding_balance: restoredBalance, status: 'active' }).eq('id', payment.loan_id);
    await db.from('payment_reversals').insert({ payment_id, reversed_by: user.id, reason: sanitizeString(reason), original_amount: payment.amount });
    await writeAuditLog({ performedBy: user.id, action: 'payment_reverse', tableName: 'payments', recordId: payment_id, oldValues: { status: 'verified', amount: payment.amount }, newValues: { status: 'reversed', reason }, ipAddress: ip });
    await sendPushNotification({ userId: loanData.user_id, title: 'Payment Reversed', body: `A payment of ₱${payment.amount.toLocaleString()} has been reversed.`, type: 'payment_reversed', referenceId: payment_id });
    return jsonResponse({ message: 'Payment reversed, balance restored' });
  } catch (err) {
    console.error('payments-reverse error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});