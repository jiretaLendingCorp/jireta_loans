
// supabase/functions/collections-decline/index.ts
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
    const { assignment_id, reason } = await req.json();
    if (!assignment_id) return errorResponse('assignment_id is required', 400, 'VALIDATION_ERROR');
    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
    const { data: assignment } = await db.from('collection_assignments').select('id, status, rider_id, assigned_by').eq('id', assignment_id).eq('rider_id', user.id).single();
    if (!assignment) return errorResponse('Assignment not found', 404, 'NOT_FOUND');
    if (assignment.status !== 'assigned') return errorResponse('Assignment is not pending', 400, 'INVALID_STATUS');
    await db.from('collection_assignments').update({ status: 'declined', response_at: new Date().toISOString(), decline_reason: reason ?? null }).eq('id', assignment_id);
    await writeAuditLog({ performedBy: user.id, action: 'collection_decline', tableName: 'collection_assignments', recordId: assignment_id, ipAddress: ip });
    if (assignment.assigned_by) await sendPushNotification({ userId: assignment.assigned_by, title: 'Collection Declined', body: 'The rider declined the collection assignment. Please reassign.', type: 'collection_declined', referenceId: assignment_id });
    return jsonResponse({ message: 'Assignment declined' });
  } catch (err) {
    console.error('collections-decline error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});