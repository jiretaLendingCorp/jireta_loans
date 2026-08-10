
// supabase/functions/payments-get-receipt/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;
    const url = new URL(req.url);
    const paymentId = url.searchParams.get('payment_id');
    if (!paymentId) return errorResponse('payment_id required', 400, 'VALIDATION_ERROR');
    const db = getAdminClient();
    const { data: payment } = await db.from('payments').select('id, status, receipt_path, loan_schedules(loan_id, loans(lender_id))').eq('id', paymentId).single();
    if (!payment) return errorResponse('Payment not found', 404, 'NOT_FOUND');
    if (user.role === ROLES.LENDER && (payment as any).loan_schedules?.loans?.lender_id !== user.id) return errorResponse('Access denied', 403, 'FORBIDDEN');
    if (user.role === ROLES.RIDER) return errorResponse('Access denied', 403, 'FORBIDDEN');
    if (!(payment as any).receipt_path) return errorResponse('Receipt not yet generated', 404, 'NOT_FOUND');
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const { data: signedUrl } = await db.storage.from('receipts').createSignedUrl((payment as any).receipt_path, 3600);
    // createSignedUrl already returns an absolute URL; only prefix with the
    // storage base URL for bare relative paths so the URL never gets doubled.
    const signedPath = (signedUrl as any)?.signedUrl ?? null;
    const fullUrl = signedPath
      ? (String(signedPath).startsWith('http')
          ? signedPath
          : `${supabaseUrl}/storage/v1${signedPath}`)
      : null;
    return jsonResponse({ signed_url: fullUrl, receipt_url: fullUrl, payment_id: paymentId });
  } catch (err) {
    console.error('payments-get-receipt error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});