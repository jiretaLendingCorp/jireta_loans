
// supabase/functions/collections-accept/index.ts
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
    const { assignment_id } = await req.json();
    if (!assignment_id) return errorResponse('assignment_id is required', 400, 'VALIDATION_ERROR');
    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
    const { data: assignment } = await db.from('collection_assignments').select('id, status, rider_id, assigned_by').eq('id', assignment_id).eq('rider_id', user.id).single();
    if (!assignment) return errorResponse('Assignment not found', 404, 'NOT_FOUND');
    if (assignment.status !== 'assigned') return errorResponse('Assignment is not in assigned status', 400, 'INVALID_STATUS');
    await db.from('collection_assignments').update({ status: 'accepted', response_at: new Date().toISOString() }).eq('id', assignment_id);
    await writeAuditLog({ performedBy: user.id, action: 'collection_accept', tableName: 'collection_assignments', recordId: assignment_id, ipAddress: ip });
    if (assignment.assigned_by) await sendPushNotification({ userId: assignment.assigned_by, title: 'Collection Accepted', body: 'The rider has accepted the collection assignment.', type: 'collection_accepted', referenceId: assignment_id });
    return jsonResponse({ message: 'Assignment accepted' });
  } catch (err) {
    console.error('collections-accept error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});