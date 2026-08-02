
// supabase/functions/loans-reject/index.ts
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

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const { loan_id, rejection_reason } = await req.json();
    if (!loan_id || !rejection_reason) return errorResponse('loan_id and rejection_reason are required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: loan } = await db.from('loans').select('id, status, user_id').eq('id', loan_id).single();
    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (['active', 'completed', 'rejected', 'cancelled'].includes(loan.status)) {
      return errorResponse(`Cannot reject loan in ${loan.status} status`, 400, 'INVALID_STATUS');
    }

    await db.from('loans').update({ status: 'rejected', rejected_by: user.id, rejection_reason: sanitizeString(rejection_reason), rejected_at: new Date().toISOString() }).eq('id', loan_id);

    await writeAuditLog({ performedBy: user.id, action: 'loan_reject', tableName: 'loans', recordId: loan_id, oldValues: { status: loan.status }, newValues: { status: 'rejected', rejection_reason }, ipAddress: ip });
    await sendPushNotification({ userId: loan.user_id, title: 'Loan Application Rejected', body: `Your loan was rejected: ${sanitizeString(rejection_reason)}`, type: 'loan_rejected', referenceId: loan_id });

    return jsonResponse({ message: 'Loan rejected' });
  } catch (err) {
    console.error('loans-reject error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
