// supabase/functions/collections-assign/index.ts
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
    const { loan_schedule_id, rider_id, collection_schedule, notes } = await req.json();
    if (!loan_schedule_id || !rider_id) return errorResponse('loan_schedule_id and rider_id are required', 400, 'VALIDATION_ERROR');
    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
    const { data: schedule } = await db.from('loan_schedules').select('id, loan_id, status, loans(status)').eq('id', loan_schedule_id).single();
    if (!schedule) return errorResponse('Schedule not found', 404, 'NOT_FOUND');
    if ((schedule as any).loans?.status !== 'active') return errorResponse('Loan must be active', 400, 'INVALID_STATUS');
    if (schedule.status === 'paid') return errorResponse('Schedule already paid', 400, 'INVALID_STATUS');
    const { data: rider } = await db.from('rider_profiles').select('is_available').eq('id', rider_id).single();
    if (!rider?.is_available) return errorResponse('Rider is not available', 400, 'VALIDATION_ERROR');
    const { data: assignment, error: insErr } = await db.from('collection_assignments').insert({
      loan_schedule_id,
      loan_id: (schedule as any).loan_id,
      rider_id,
      assigned_by: user.id,
      collection_schedule: collection_schedule ?? null,
      collection_notes: notes ?? null,
      status: 'assigned',
    }).select('id').single();
    if (insErr) return errorResponse('Failed to create assignment', 500, 'SERVER_ERROR');
    await writeAuditLog({ performedBy: user.id, action: 'collection_assign', tableName: 'collection_assignments', recordId: assignment.id, ipAddress: ip });
    await sendPushNotification({ userId: rider_id, title: 'New Collection Assignment', body: 'You have a new cash collection assignment. Please review and accept.', type: 'collection_assigned', referenceId: assignment.id });
    return jsonResponse({ message: 'Collection assigned', assignment_id: assignment.id }, 201);
  } catch (err) {
    console.error('collections-assign error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});