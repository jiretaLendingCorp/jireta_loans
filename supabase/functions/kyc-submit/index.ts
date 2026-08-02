// supabase/functions/kyc-submit/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { notifyStaff } from '../_shared/notifications.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.LENDER);
    if (roleCheck) return roleCheck;

    const body = await req.json();
    const { documents } = body;

    if (!documents || !Array.isArray(documents) || documents.length === 0) {
      return errorResponse('At least one document is required', 400, 'VALIDATION_ERROR');
    }

    const allowedTypes = ['valid_id', 'selfie', 'proof_of_billing', 'proof_of_income', 'other'];
    for (const doc of documents) {
      if (!doc.document_type || !doc.file_url) return errorResponse('Each document needs document_type and file_url', 400, 'VALIDATION_ERROR');
      if (!allowedTypes.includes(doc.document_type)) return errorResponse(`Invalid document_type: ${doc.document_type}`, 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const docsToInsert = documents.map((doc: any) => ({
      user_id: user.id,
      document_type: doc.document_type,
      file_url: doc.file_url,
      file_name: doc.file_name ?? null,
      status: 'submitted',
    }));

    await db.from('kyc_documents').insert(docsToInsert);
    await db.from('lender_profiles').update({ kyc_status: 'submitted' }).eq('user_id', user.id);

    await writeAuditLog({ performedBy: user.id, action: 'kyc_submit', tableName: 'kyc_documents', recordId: user.id, ipAddress: ip });
    await notifyStaff({ title: 'KYC Submitted', body: 'A lender has submitted KYC documents for review.', type: 'kyc_submitted', referenceId: user.id });

    return jsonResponse({ message: 'KYC documents submitted successfully' }, 201);
  } catch (err) {
    console.error('kyc-submit error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
