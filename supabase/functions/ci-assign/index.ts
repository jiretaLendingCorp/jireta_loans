// supabase/functions/ci-assign/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { validateUUID, sanitizeString } from '../_shared/validators.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const { loan_id, rider_id, investigation_notes, deadline } = await req.json();

    if (!loan_id || !rider_id) return errorResponse('loan_id and rider_id are required', 400, 'VALIDATION_ERROR');
    if (!validateUUID(loan_id) || !validateUUID(rider_id)) return errorResponse('Invalid UUID format', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();

    const { data: loan } = await db
      .from('loans')
      .select('id, status, lender_id')
      .eq('id', loan_id)
      .single();

    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (!['under_review', 'ci_assigned'].includes(loan.status)) {
      return errorResponse('Loan must be under_review to assign CI', 409, 'INVALID_STATUS');
    }

    const { data: rider } = await db
      .from('rider_profiles')
      .select('id, is_available')
      .eq('id', rider_id)
      .single();

    if (!rider) return errorResponse('Rider not found', 404, 'NOT_FOUND');
    if (!rider.is_available) return errorResponse('Rider is not available', 409, 'RIDER_UNAVAILABLE');

    const { data: ci, error: ciErr } = await db.from('credit_investigations').insert({
      loan_id,
      rider_id,
      assigned_by: authResult.id,
      investigation_notes: investigation_notes ? sanitizeString(investigation_notes) : null,
      deadline: deadline ?? null,
      status: 'assigned',
    }).select().single();

    if (ciErr || !ci) return errorResponse('Failed to create CI assignment', 500, 'SERVER_ERROR');

    await db.from('loans').update({ status: 'ci_assigned' }).eq('id', loan_id);
    await db.from('rider_profiles').update({ is_available: false }).eq('id', rider_id);

    await writeAuditLog({
      performedBy: authResult.id,
      action: 'ci_assigned',
      tableName: 'credit_investigations',
      recordId: ci.id,
      newValues: { loan_id, rider_id, assigned_by: authResult.id },
      ipAddress: req.headers.get('x-forwarded-for') ?? undefined,
    });

    await sendPushNotification({
      userId: rider_id,
      title: 'New CI Assignment',
      body: 'You have been assigned a credit investigation. Tap to view details.',
      type: 'ci_assigned',
      referenceId: ci.id,
    });

    await sendPushNotification({
      userId: authResult.id,
      title: 'CI Assignment Confirmed',
      body: `Credit investigation assigned to rider successfully.`,
      type: 'ci_assigned',
      referenceId: ci.id,
    });

    return jsonResponse({ ci_id: ci.id, message: 'CI assigned successfully' }, 201);
  } catch (err) {
    console.error('ci-assign error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});