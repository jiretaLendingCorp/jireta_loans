
// supabase/functions/payments-xendit-webhook/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { verifyWebhookToken } from '../_shared/xendit.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { getPaymentLoanId, getLoanFinancials, round2 } from '../_shared/loan_financials.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    if (!verifyWebhookToken(req)) return errorResponse('Invalid webhook token', 401, 'UNAUTHORIZED');
    const body = await req.json();
    const { id: xenditId, status, amount } = body;
    if (!xenditId || !status) return errorResponse('Invalid webhook payload', 400, 'VALIDATION_ERROR');
    const db = getAdminClient();
    const { data: payment } = await db.from('payments').select('id, loan_schedule_id, collection_assignment_id, status').eq('xendit_payment_id', xenditId).single();
    if (!payment) { await db.from('xendit_logs').insert({ event_type: 'payment', xendit_id: xenditId, status: 'unmatched', payload: body }); return jsonResponse({ received: true }); }
    if (payment.status === 'verified') return jsonResponse({ already_processed: true });
    if (status === 'PAID') {
      // Re-verify the paid amount against the installment the lender actually
      // owes before crediting it. A mismatched payload (replayed, tampered, or
      // a duplicate invoice amount) must not over-credit the balance.
      let expectedAmount: number | null = null;
      if (payment.loan_schedule_id) {
        const { data: schedule } = await db
          .from('loan_schedules')
          .select('amount_due')
          .eq('id', payment.loan_schedule_id)
          .single();
        expectedAmount = schedule ? Number(schedule.amount_due) : null;
      }
      const paidAmount = Number(amount ?? 0);
      const amountOk = expectedAmount !== null && round2(paidAmount) === round2(expectedAmount);
      if (!amountOk) {
        await db.from('xendit_logs').insert({ event_type: 'payment', xendit_id: xenditId, payment_id: payment.id, status: 'amount_mismatch', payload: body });
        console.error(`[payments-xendit-webhook] amount mismatch for payment ${payment.id}: paid=${paidAmount} expected=${expectedAmount}`);
        return errorResponse('Payment amount does not match the installment', 422, 'AMOUNT_MISMATCH');
      }
      await db.from('payments').update({ status: 'verified', paid_at: new Date().toISOString() }).eq('id', payment.id);
      const loanId = await getPaymentLoanId(db, payment);
      if (loanId) {
        const { data: loan } = await db.from('loans').select('id, lender_id, status').eq('id', loanId).single();
        const financials = await getLoanFinancials(db, loanId);
        const newBalance = Math.max(0, financials?.outstanding_balance ?? 0);
        await db.from('loans').update({ ...(newBalance <= 0 ? { status: 'completed' } : {}) }).eq('id', loanId);
        if (loan?.lender_id) {
          await writeAuditLog({ performedBy: 'system', action: 'xendit_payment_verified', tableName: 'payments', recordId: payment.id, newValues: { amount, xendit_id: xenditId } });
          await sendPushNotification({ userId: loan.lender_id, title: 'GCash Payment Confirmed', body: `Payment of ₱${(amount ?? 0).toLocaleString()} confirmed. Remaining balance: ₱${newBalance.toLocaleString()}`, type: 'payment_verified', referenceId: payment.id });
        }
      }
    }
    await db.from('xendit_logs').insert({ event_type: 'payment', xendit_id: xenditId, payment_id: payment.id, status, payload: body });
    return jsonResponse({ processed: true });
  } catch (err) {
    console.error('payments-xendit-webhook error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});