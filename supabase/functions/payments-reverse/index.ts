
// supabase/functions/payments-reverse/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeString } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { getPaymentLoanId, getLoanFinancials } from '../_shared/loan_financials.ts';

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
    const { data: payment } = await db.from('payments').select('id, status, amount, loan_schedule_id, collection_assignment_id').eq('id', payment_id).single();
    if (!payment) return errorResponse('Payment not found', 404, 'NOT_FOUND');
    if (payment.status !== 'verified') return errorResponse('Only verified payments can be reversed', 400, 'INVALID_STATUS');
    await db.from('payments').update({ status: 'reversed' }).eq('id', payment_id);
    await db.from('payment_reversals').insert({ payment_id, reversed_by: user.id, reason: sanitizeString(reason) });
    const loanId = await getPaymentLoanId(db, payment);
    const financials = loanId ? await getLoanFinancials(db, loanId) : null;
    const restoredBalance = Math.round(((financials?.outstanding_balance ?? 0) + Number(payment.amount)) * 100) / 100;
    if (loanId) await db.from('loans').update({ status: 'active' }).eq('id', loanId);
    const lenderId = loanId
      ? (await db.from('loans').select('lender_id').eq('id', loanId).single()).data?.lender_id
      : null;
    await writeAuditLog({ performedBy: user.id, action: 'payment_reverse', tableName: 'payments', recordId: payment_id, oldValues: { status: 'verified', amount: payment.amount }, newValues: { status: 'reversed', reason }, ipAddress: ip });
    if (lenderId) {
      await sendPushNotification({ userId: lenderId, title: 'Payment Reversed', body: `A payment of ₱${Number(payment.amount).toLocaleString()} has been reversed.`, type: 'payment_reversed', referenceId: payment_id });
    }
    return jsonResponse({ message: 'Payment reversed, balance restored' });
  } catch (err) {
    console.error('payments-reverse error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});