// supabase/functions/disbursements-rider-delivery/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { validateUUID } from '../_shared/validators.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const body = await req.json().catch(() => ({}));
    const { loan_id, rider_id, delivery_date, notes } = body;

    if (!loan_id || !validateUUID(loan_id)) return errorResponse('Valid loan_id is required', 400, 'VALIDATION_ERROR');
    if (!rider_id || !validateUUID(rider_id)) return errorResponse('Valid rider_id is required', 400, 'VALIDATION_ERROR');
    if (!delivery_date) return errorResponse('delivery_date is required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();

    const { data: loan } = await db
      .from('loans')
      .select('id, loan_number, lender_id, principal_amount, status, disbursement_method')
      .eq('id', loan_id)
      .single();

    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (loan.status !== 'approved') return errorResponse('Loan must be approved to disburse', 400, 'INVALID_STATUS');
    if (loan.disbursement_method) return errorResponse('Loan already disbursed', 400, 'DUPLICATE');

    const { data: rider } = await db
      .from('rider_profiles')
      .select('id, is_available')
      .eq('user_id', rider_id)
      .single();

    if (!rider) return errorResponse('Rider not found', 404, 'NOT_FOUND');
    if (!rider.is_available) return errorResponse('Rider is not available', 400, 'INVALID_STATUS');

    const amount = Number(loan.principal_amount);
    const now = new Date().toISOString();

    const { data: disbursement, error: disbErr } = await db
      .from('disbursements')
      .insert({
        loan_id,
        lender_id: loan.lender_id,
        disbursement_method: 'rider_delivery',
        amount,
        rider_id,
        delivery_date,
        notes: notes ?? null,
        assigned_by: authResult.id,
        disbursed_at: now,
        status: 'pending',
      })
      .select()
      .single();

    if (disbErr) throw disbErr;

    await writeAuditLog({
      performedBy: authResult.id,
      action: 'disburse_rider_delivery',
      tableName: 'disbursements',
      recordId: disbursement.id,
      newValues: { loan_id, rider_id, amount, delivery_date },
    });

    await sendPushNotification({
      userId: rider_id,
      title: 'New Cash Delivery Assignment',
      body: `You have been assigned to deliver ₱${amount.toLocaleString()} for loan ${loan.loan_number} on ${delivery_date}.`,
      type: 'disbursement',
      referenceId: disbursement.id,
      sentBy: authResult.id,
    });

    await sendPushNotification({
      userId: loan.lender_id,
      title: 'Loan Delivery Scheduled',
      body: `A rider has been assigned to deliver your loan of ₱${amount.toLocaleString()} on ${delivery_date}.`,
      type: 'disbursement',
      referenceId: loan_id,
      sentBy: authResult.id,
    });

    return jsonResponse({ success: true, disbursement });
  } catch (err) {
    console.error('disbursements-rider-delivery error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});