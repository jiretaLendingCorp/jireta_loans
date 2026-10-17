
// supabase/functions/payments-xendit-webhook/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { verifyWebhookToken } from '../_shared/xendit.ts';
import { getAdminClient } from '../_shared/db.ts';
import { settlePaidXenditPayment } from '../_shared/payment_settlement.ts';

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
    // Tinatanggap ang PAID at SETTLED: may mga channel na `SETTLED` ang huling
    // status na ipinapadala, at kung PAID lang ang haharangin ay mananatiling
    // `pending` ang bayad kahit bayad na.
    if (status === 'PAID' || status === 'SETTLED') {
      // Iisang settlement path ito at ang `?fn=sync-payment` (reconciliation),
      // para pareho ang epekto sa balance kahit saan galing ang kumpirmasyon.
      // Sinusuri rin nito ang amount laban sa `loan_schedules.amount_due` —
      // ang maling/replayed na payload ay hindi nagpapababa ng utang.
      const settled = await settlePaidXenditPayment(db, {
        paymentId: payment.id,
        xenditId,
        amount: Number(body.paid_amount ?? amount ?? 0),
        source: 'webhook',
      });
      if (!settled.ok) {
        await db.from('xendit_logs').insert({ event_type: 'payment', xendit_id: xenditId, payment_id: payment.id, status: 'amount_mismatch', payload: body });
        console.error(`[payments-xendit-webhook] amount mismatch for payment ${payment.id}: paid=${settled.paidAmount} expected=${settled.expectedAmount}`);
        return errorResponse('Payment amount does not match the installment', 422, 'AMOUNT_MISMATCH');
      }
    }
    await db.from('xendit_logs').insert({ event_type: 'payment', xendit_id: xenditId, payment_id: payment.id, status, payload: body });
    return jsonResponse({ processed: true });
  } catch (err) {
    console.error('payments-xendit-webhook error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});