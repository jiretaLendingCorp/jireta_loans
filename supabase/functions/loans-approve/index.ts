// supabase/functions/loans-approve/index.ts
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

    const { loan_id, notes } = await req.json();
    if (!loan_id) return errorResponse('loan_id is required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: loan } = await db.from('loans')
      .select('id, status, lender_id, lender_profiles(kyc_status)')
      .eq('id', loan_id).single();

    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (loan.status !== 'ci_completed') return errorResponse(`Loan must be in ci_completed status, current: ${loan.status}`, 400, 'INVALID_STATUS');

    const lp = (loan as any).lender_profiles;
    if (lp?.kyc_status !== 'verified') return errorResponse('Lender KYC must be verified', 400, 'KYC_NOT_VERIFIED');

    const { data: blacklist } = await db.from('blacklist').select('id').eq('lender_id', loan.lender_id).eq('is_active', true).maybeSingle();
    if (blacklist) return errorResponse('Lender is blacklisted', 400, 'BLACKLISTED');

    const { data: ci } = await db.from('credit_investigations').select('id, status').eq('loan_id', loan_id).eq('status', 'completed').maybeSingle();
    if (!ci) return errorResponse('CI report must be completed before approval', 400, 'INVALID_STATUS');

    await db.from('loans').update({ status: 'approved', approved_by: user.id }).eq('id', loan_id);

    await writeAuditLog({ performedBy: user.id, action: 'loan_approve', tableName: 'loans', recordId: loan_id, oldValues: { status: loan.status }, newValues: { status: 'approved' }, ipAddress: ip });
    await sendPushNotification({ userId: loan.lender_id, title: 'Loan Approved', body: 'Congratulations! Your loan application has been approved.', type: 'loan_approved', referenceId: loan_id });

    return jsonResponse({ message: 'Loan approved successfully' });
  } catch (err) {
    console.error('loans-approve error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
