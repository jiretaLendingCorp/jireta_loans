// supabase/functions/collections-record/index.ts
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

    const idempotencyKey = req.headers.get('x-idempotency-key');
    if (!idempotencyKey) return errorResponse('x-idempotency-key header required', 400, 'VALIDATION_ERROR');

    const { assignment_id, amount_collected, notes, latitude, longitude } = await req.json();
    if (!assignment_id || amount_collected === undefined) return errorResponse('assignment_id and amount_collected required', 400, 'VALIDATION_ERROR');
    if (amount_collected <= 0) return errorResponse('Amount must be positive', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: existing } = await db.from('payments').select('id').eq('idempotency_key', idempotencyKey).maybeSingle();
    if (existing) return errorResponse('Duplicate request detected', 409, 'IDEMPOTENCY_CONFLICT');

    const { data: assignment } = await db.from('collection_assignments')
      .select('id, status, rider_id, loan_id, loan_schedule_id, assigned_by, loans(lender_id, outstanding_balance)')
      .eq('id', assignment_id).eq('rider_id', user.id).single();
    if (!assignment) return errorResponse('Assignment not found', 404, 'NOT_FOUND');
    if (!['accepted'].includes(assignment.status)) return errorResponse('Assignment must be accepted first', 400, 'INVALID_STATUS');

    const loanData = (assignment as any).loans;
    if (amount_collected > loanData.outstanding_balance) return errorResponse('Amount exceeds outstanding balance', 400, 'VALIDATION_ERROR');

    const newBalance = Math.round((loanData.outstanding_balance - amount_collected) * 100) / 100;

    const { data: payment, error: payErr } = await db.from('payments').insert({
      loan_id: assignment.loan_id,
      loan_schedule_id: assignment.loan_schedule_id,
      amount: amount_collected,
      payment_method: 'rider_collection',
      status: 'verified',
      recorded_by: user.id,
      collection_assignment_id: assignment_id,
      notes: notes ?? null,
      idempotency_key: idempotencyKey,
    }).select('id').single();
    if (payErr) return errorResponse('Failed to record payment', 500, 'SERVER_ERROR');

    await db.from('loan_schedules').update({ status: 'paid', paid_at: new Date().toISOString(), amount_paid: amount_collected }).eq('id', assignment.loan_schedule_id);
    await db.from('loans').update({ outstanding_balance: newBalance, ...(newBalance <= 0 ? { status: 'completed' } : {}) }).eq('id', assignment.loan_id);
    await db.from('collection_assignments').update({ status: 'in_progress', completed_at: new Date().toISOString(), amount_collected }).eq('id', assignment_id);

    await writeAuditLog({ performedBy: user.id, action: 'collection_record', tableName: 'payments', recordId: payment.id, newValues: { amount: amount_collected, method: 'rider_collection' }, ipAddress: ip });
    await sendPushNotification({ userId: loanData.lender_id, title: 'Payment Collected', body: `Payment of ₱${amount_collected.toLocaleString()} has been collected. Remaining: ₱${newBalance.toLocaleString()}`, type: 'payment_collected', referenceId: payment.id });

    return jsonResponse({ message: 'Payment recorded', payment_id: payment.id, new_balance: newBalance }, 201);
  } catch (err) {
    console.error('collections-record error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});