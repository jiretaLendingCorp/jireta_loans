
// supabase/functions/ci-submit-report/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeString } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { notifyStaff } from '../_shared/notifications.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;
    const roleCheck = requireRole(user, ROLES.RIDER);
    if (roleCheck) return roleCheck;
    const { ci_id, report_summary } = await req.json();
    if (!ci_id || !report_summary) return errorResponse('ci_id and report_summary are required', 400, 'VALIDATION_ERROR');
    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
    const { data: ci } = await db.from('credit_investigations').select('id, status, rider_id, loan_id').eq('id', ci_id).eq('rider_id', user.id).single();
    if (!ci) return errorResponse('CI not found', 404, 'NOT_FOUND');
    if (!['accepted', 'in_progress'].includes(ci.status)) return errorResponse('CI is not in progress', 400, 'INVALID_STATUS');
    const { count: docCount } = await db.from('ci_documents').select('*', { count: 'exact', head: true }).eq('ci_id', ci_id);
    if ((docCount ?? 0) === 0) return errorResponse('At least 1 document must be uploaded', 400, 'VALIDATION_ERROR');
    await db.from('credit_investigations').update({ status: 'completed', report_summary: sanitizeString(report_summary), completed_at: new Date().toISOString() }).eq('id', ci_id);
    await db.from('loans').update({ status: 'ci_completed' }).eq('id', ci.loan_id);
    await db.from('rider_profiles').update({ is_available: true }).eq('user_id', user.id);
    await writeAuditLog({ performedBy: user.id, action: 'ci_submit_report', tableName: 'credit_investigations', recordId: ci_id, ipAddress: ip });
    await notifyStaff({ title: 'CI Report Submitted', body: 'A rider has submitted a credit investigation report. Ready for approval.', type: 'ci_completed', referenceId: ci.loan_id });
    return jsonResponse({ message: 'CI report submitted. Loan is ready for approval.' });
  } catch (err) {
    console.error('ci-submit-report error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});