
// supabase/functions/loans-request-ci/index.ts
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

    const { loan_id } = await req.json();
    if (!loan_id) return errorResponse('loan_id is required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: loan } = await db.from('loans').select('id, status, lender_id').eq('id', loan_id).single();
    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (!['pending', 'under_review'].includes(loan.status)) return errorResponse('Loan must be pending or under_review to request CI', 400, 'INVALID_STATUS');

    // CI is REQUESTED here, not assigned. The `ci_assigned` status is reserved
    // for a loan with an actual credit_investigations row + an available rider
    // (ci-assign). Flagging as `ci_required` keeps the list honest: without an
    // assignment the loan shows "CI Required", never "CI Assigned".
    await db.from('loans').update({ status: 'ci_required' }).eq('id', loan_id);
    await writeAuditLog({ performedBy: user.id, action: 'request_ci', tableName: 'loans', recordId: loan_id, oldValues: { status: loan.status }, newValues: { status: 'ci_required' }, ipAddress: ip });
    await sendPushNotification({ userId: loan.lender_id, title: 'Credit Investigation Required', body: 'Your loan requires a credit investigation. A rider will visit your address.', type: 'ci_required', referenceId: loan_id });

    return jsonResponse({ message: 'CI requested' });
  } catch (err) {
    console.error('loans-request-ci error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});