// supabase/functions/disbursements-xendit-webhook/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { verifyWebhookToken } from '../_shared/xendit.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    if (!verifyWebhookToken(req)) {
      return errorResponse('Invalid webhook token', 401, 'UNAUTHORIZED');
    }

    const payload = await req.json();
    const { id: xenditId, status, external_id } = payload;

    if (!xenditId || !status) {
      return errorResponse('Invalid webhook payload', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();

    const { data: disbursement, error } = await db
      .from('disbursements')
      .select('id, loan_id, lender_id, amount')
      .eq('xendit_disbursement_id', xenditId)
      .single();

    if (error || !disbursement) {
      console.warn('Disbursement not found for xendit id:', xenditId);
      return jsonResponse({ received: true });
    }

    const xenditStatus = status.toUpperCase();
    const isCompleted = xenditStatus === 'COMPLETED' || xenditStatus === 'SUCCESS';
    const isFailed = xenditStatus === 'FAILED';

    await db
      .from('disbursements')
      .update({ xendit_status: xenditStatus, status: isCompleted ? 'completed' : isFailed ? 'failed' : 'pending' })
      .eq('id', disbursement.id);

    await db.from('xendit_logs').insert({
      type: 'disbursement_webhook',
      xendit_id: xenditId,
      external_id: external_id ?? null,
      status: xenditStatus,
      payload,
    });

    if (isCompleted) {
      await db
        .from('loans')
        .update({ status: 'active', disbursement_method: 'gcash', disbursed_at: new Date().toISOString() })
        .eq('id', disbursement.loan_id);

      await sendPushNotification({
        userId: disbursement.lender_id,
        title: 'GCash Transfer Successful',
        body: `₱${Number(disbursement.amount).toLocaleString()} has been transferred to your GCash account.`,
        type: 'disbursement',
        referenceId: disbursement.loan_id,
      });
    }

    if (isFailed) {
      await sendPushNotification({
        userId: disbursement.lender_id,
        title: 'GCash Transfer Failed',
        body: 'Your loan disbursement via GCash failed. Please contact our office.',
        type: 'disbursement',
        referenceId: disbursement.loan_id,
      });
    }

    await writeAuditLog({
      performedBy: 'system',
      action: 'disbursement_webhook',
      tableName: 'disbursements',
      recordId: disbursement.id,
      newValues: { xendit_status: xenditStatus, xendit_id: xenditId },
    });

    return jsonResponse({ received: true });
  } catch (err) {
    console.error('disbursements-xendit-webhook error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});