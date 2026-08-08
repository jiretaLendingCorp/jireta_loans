
// supabase/functions/loans-apply-penalty/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { getLoanFinancials, hasPenaltyApplied } from '../_shared/loan_financials.ts';

const PENALTY_RATE = 0.20;

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const { loan_id, reason } = await req.json();
    if (!loan_id) return errorResponse('loan_id is required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: loan } = await db.from('loans').select('id, status, lender_id').eq('id', loan_id).single();
    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (loan.status !== 'overdue') return errorResponse('Penalty can only be applied to overdue loans', 400, 'INVALID_STATUS');

    if (await hasPenaltyApplied(db, loan_id)) return errorResponse('Penalty already applied', 400, 'DUPLICATE');

    const financials = await getLoanFinancials(db, loan_id);
    const penaltyAmount = Math.round((financials?.total_payable ?? 0) * PENALTY_RATE * 100) / 100;
    const newBalance = Math.round(((financials?.outstanding_balance ?? 0) + penaltyAmount) * 100) / 100;

    await db.from('penalty_logs').insert({ loan_id, applied_by: user.id, penalty_rate: PENALTY_RATE, penalty_basis: financials?.total_payable ?? 0, penalty_amount: penaltyAmount, reason: reason ?? 'Overdue penalty applied' });

    await writeAuditLog({ performedBy: user.id, action: 'apply_penalty', tableName: 'penalty_logs', recordId: loan_id, oldValues: { outstanding_balance: financials?.outstanding_balance }, newValues: { outstanding_balance: newBalance, penalty_amount: penaltyAmount }, ipAddress: ip });
    await sendPushNotification({ userId: loan.lender_id, title: 'Overdue Penalty Applied', body: `A 20% penalty of ₱${penaltyAmount.toLocaleString()} has been added to your outstanding balance.`, type: 'penalty_applied', referenceId: loan_id });

    return jsonResponse({ message: 'Penalty applied', penalty_amount: penaltyAmount, new_balance: newBalance });
  } catch (err) {
    console.error('loans-apply-penalty error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
