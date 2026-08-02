
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

    const { kyc_doc_id, action, rejection_notes } = await req.json();
    if (!kyc_doc_id || !['verified', 'rejected'].includes(action)) {
      return errorResponse('kyc_doc_id and action (verified|rejected) are required', 400, 'VALIDATION_ERROR');
    }
    if (action === 'rejected' && !rejection_notes) {
      return errorResponse('rejection_notes required when rejecting', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: doc } = await db.from('kyc_documents').select('id, user_id, status').eq('id', kyc_doc_id).single();
    if (!doc) return errorResponse('KYC document not found', 404, 'NOT_FOUND');

    await db.from('kyc_documents').update({
      status: action,
      verified_by: user.id,
      verified_at: new Date().toISOString(),
      rejection_notes: rejection_notes ?? null,
    }).eq('id', kyc_doc_id);

    const { data: allDocs } = await db.from('kyc_documents').select('status').eq('user_id', doc.user_id);
    const anyRejected = allDocs?.some((d: any) => d.status === 'rejected');
    const allVerified = allDocs?.every((d: any) => d.status === 'verified');

    let newKycStatus = 'under_review';
    if (anyRejected) newKycStatus = 'rejected';
    else if (allVerified) newKycStatus = 'verified';

    await db.from('lender_profiles').update({ kyc_status: newKycStatus }).eq('user_id', doc.user_id);

    await writeAuditLog({ performedBy: user.id, action: `kyc_doc_${action}`, tableName: 'kyc_documents', recordId: kyc_doc_id, ipAddress: ip });
    await sendPushNotification({
      userId: doc.user_id,
      title: action === 'verified' ? 'KYC Document Verified' : 'KYC Document Rejected',
      body: action === 'verified' ? 'Your document has been verified.' : `Document rejected: ${rejection_notes}`,
      type: 'kyc_update',
    });

    return jsonResponse({ message: `Document ${action}`, kyc_status: newKycStatus });
  } catch (err) {
    console.error('kyc-verify error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
