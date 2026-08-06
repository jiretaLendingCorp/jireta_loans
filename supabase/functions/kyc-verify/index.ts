
// supabase/functions/kyc-verify/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const body = await req.json();
    const { kyc_doc_id, lender_id, action, rejection_notes } = body;
    if (!['verified', 'rejected'].includes(action)) {
      return errorResponse('action (verified|rejected) is required', 400, 'VALIDATION_ERROR');
    }
    if (action === 'rejected' && !rejection_notes) {
      return errorResponse('rejection_notes required when rejecting', 400, 'VALIDATION_ERROR');
    }
    if (!kyc_doc_id && !lender_id) {
      return errorResponse('kyc_doc_id or lender_id is required', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
    const now = new Date().toISOString();

    // Resolve the lender_id: direct lender_id, or from a single document id.
    let targetLenderId = lender_id as string | null;
    let singleDocId: string | null = null;
    if (kyc_doc_id) {
      const { data: doc } = await db.from('kyc_documents').select('id, lender_id, status').eq('id', kyc_doc_id).single();
      if (!doc) return errorResponse('KYC document not found', 404, 'NOT_FOUND');
      targetLenderId = (doc as any).lender_id;
      singleDocId = kyc_doc_id;
    }

    // When lender_id is given, verify/reject ALL non-final docs for that lender
    // in a single operation. When kyc_doc_id is given, only that doc is updated.
    let query = db.from('kyc_documents').update({
      status: action,
      reviewed_by: user.id,
      reviewed_at: now,
      rejection_notes: rejection_notes ?? null,
    }).eq('lender_id', targetLenderId);
    if (singleDocId) query = query.eq('id', singleDocId);
    const { error: updateError } = await query;
    if (updateError) return errorResponse('Failed to update KYC documents', 500, 'DB_ERROR');

    const { data: allDocs } = await db.from('kyc_documents').select('status').eq('lender_id', targetLenderId);
    const anyRejected = allDocs?.some((d: any) => d.status === 'rejected');
    const allVerified = allDocs?.every((d: any) => d.status === 'verified');

    let newKycStatus = 'submitted';
    if (anyRejected) newKycStatus = 'rejected';
    else if (allVerified) newKycStatus = 'verified';

    await db.from('lender_profiles').update({ kyc_status: newKycStatus }).eq('id', targetLenderId);

    await writeAuditLog({
      performedBy: user.id,
      action: singleDocId ? `kyc_doc_${action}` : `kyc_all_${action}`,
      tableName: 'kyc_documents',
      recordId: singleDocId ?? targetLenderId,
      ipAddress: ip,
    });
    await sendPushNotification({
      userId: targetLenderId,
      title: action === 'verified' ? 'KYC Verified' : 'KYC Rejected',
      body: action === 'verified'
        ? 'All of your KYC documents have been verified.'
        : `KYC rejected: ${rejection_notes}`,
      type: 'kyc_update',
      referenceId: singleDocId ?? targetLenderId,
      sentBy: user.id,
    });

    return jsonResponse({
      message: singleDocId ? `Document ${action}` : `All documents ${action}`,
      kyc_status: newKycStatus,
      lender_id: targetLenderId,
    });
  } catch (err) {
    console.error('kyc-verify error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
