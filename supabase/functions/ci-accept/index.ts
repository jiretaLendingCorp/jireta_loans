// supabase/functions/ci-accept/index.ts
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
    const roleCheck = requireRole(user, ROLES.RIDER);
    if (roleCheck) return roleCheck;
    const { ci_id } = await req.json();
    if (!ci_id) return errorResponse('ci_id is required', 400, 'VALIDATION_ERROR');
    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
    const { data: ci } = await db.from('credit_investigations').select('id, status, assigned_by, rider_id, loan_id').eq('id', ci_id).eq('rider_id', user.id).single();
    if (!ci) return errorResponse('CI assignment not found', 404, 'NOT_FOUND');
    if (ci.status !== 'pending') return errorResponse('CI is not in pending status', 400, 'INVALID_STATUS');
    await db.from('credit_investigations').update({ status: 'accepted', response_at: new Date().toISOString() }).eq('id', ci_id);
    await db.from('loans').update({ status: 'ci_assigned' }).eq('id', ci.loan_id);
    await db.from('rider_profiles').update({ is_available: false }).eq('user_id', user.id);
    await writeAuditLog({ performedBy: user.id, action: 'ci_accept', tableName: 'credit_investigations', recordId: ci_id, ipAddress: ip });
    if (ci.assigned_by) await sendPushNotification({ userId: ci.assigned_by, title: 'CI Accepted', body: 'The rider has accepted the credit investigation assignment.', type: 'ci_accepted', referenceId: ci_id });
    return jsonResponse({ message: 'CI assignment accepted' });
  } catch (err) {
    console.error('ci-accept error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
