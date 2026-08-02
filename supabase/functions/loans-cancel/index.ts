
// supabase/functions/loans-cancel/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const { loan_id } = await req.json();
    if (!loan_id) return errorResponse('loan_id is required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: loan } = await db.from('loans').select('id, status, user_id').eq('id', loan_id).single();
    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');

    if (user.role === ROLES.LENDER && loan.user_id !== user.id) {
      return errorResponse('Access denied', 403, 'FORBIDDEN');
    }

    if (!['pending', 'under_review'].includes(loan.status)) {
      return errorResponse(`Cannot cancel loan in ${loan.status} status`, 400, 'INVALID_STATUS');
    }

    await db.from('loans').update({ status: 'cancelled', cancelled_by: user.id, cancelled_at: new Date().toISOString() }).eq('id', loan_id);
    await writeAuditLog({ performedBy: user.id, action: 'loan_cancel', tableName: 'loans', recordId: loan_id, oldValues: { status: loan.status }, newValues: { status: 'cancelled' }, ipAddress: ip });

    return jsonResponse({ message: 'Loan cancelled' });
  } catch (err) {
    console.error('loans-cancel error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});