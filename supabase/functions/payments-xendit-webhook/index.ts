
// supabase/functions/payments-xendit-webhook/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { verifyWebhookToken } from '../_shared/xendit.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    if (!verifyWebhookToken(req)) return errorResponse('Invalid webhook token', 401, 'UNAUTHORIZED');
    const body = await req.json();
    const { id: xenditId, status, external_id, amount } = body;
    if (!xenditId || !status) return errorResponse('Invalid webhook payload', 400, 'VALIDATION_ERROR');
    const db = getAdminClient();
    const { data: payment } = await db.from('payments').select('id, loan_id, loan_schedule_id, status, loans(user_id, outstanding_balance)').eq('xendit_invoice_id', xenditId).single();
    if (!payment) { await db.from('xendit_logs').insert({ reference_type: 'invoice', xendit_id: xenditId, external_id, amount: amount ?? 0, status: 'unmatched', payload: body }); return jsonResponse({ received: true }); }
    if (payment.status === 'verified') return jsonResponse({ already_processed: true });
    if (status === 'PAID') {
      await db.from('payments').update({ status: 'verified', paid_at: new Date().toISOString() }).eq('id', payment.id);
      await db.from('loan_schedules').update({ status: 'paid', paid_at: new Date().toISOString(), amount_paid: amount }).eq('id', payment.loan_schedule_id);
      const loanData = (payment as any).loans;
      const newBalance = Math.round((loanData.outstanding_balance - (amount ?? 0)) * 100) / 100;
      await db.from('loans').update({ outstanding_balance: newBalance, ...(newBalance <= 0 ? { status: 'completed', completed_at: new Date().toISOString() } : {}) }).eq('id', payment.loan_id);
      await writeAuditLog({ performedBy: 'system', action: 'xendit_payment_verified', tableName: 'payments', recordId: payment.id, newValues: { amount, xendit_id: xenditId } });
      await sendPushNotification({ userId: loanData.user_id, title: 'GCash Payment Confirmed', body: `Payment of ₱${(amount ?? 0).toLocaleString()} confirmed. Remaining balance: ₱${newBalance.toLocaleString()}`, type: 'payment_verified', referenceId: payment.id });
    }
    await db.from('xendit_logs').insert({ reference_type: 'invoice', xendit_id: xenditId, external_id, amount: amount ?? 0, status, payload: body });
    return jsonResponse({ processed: true });
  } catch (err) {
    console.error('payments-xendit-webhook error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});