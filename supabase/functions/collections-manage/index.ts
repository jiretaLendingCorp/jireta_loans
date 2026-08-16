// supabase/functions/collections-manage/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   collections-assign         →  ?fn=assign
//   collections-accept         →  ?fn=accept
//   collections-decline        →  ?fn=decline
//   collections-record         →  ?fn=record
//   collections-upload-proof   →  ?fn=upload-proof
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification, notifyStaff } from '../_shared/notifications.ts';
import { embedAsObject } from '../_shared/types.ts';
import {
  getSchedulePayment,
  scheduleStatus,
  getLoanFinancials,
} from '../_shared/loan_financials.ts';

// ── [moved from collections-upload-proof] ───────────────────────────────────
const BUCKET = 'collection-proofs';

// ── [moved from collections-upload-proof] ───────────────────────────────────
const COLUMN_BY_TYPE: Record<string, string> = {
  proof_photo: 'proof_photo',
  scene_photo: 'collection_photo',
  signature: 'borrower_signature',
};

// ── [moved from collections-upload-proof] ───────────────────────────────────
function decodeBase64(content: string): Uint8Array {
  const binary = atob(content);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

// ── [moved from collections-upload-proof] ───────────────────────────────────
function extFromMime(mimeType?: string): string {
  switch ((mimeType ?? '').toLowerCase()) {
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    case 'image/gif':
      return 'gif';
    case 'image/bmp':
      return 'bmp';
    default:
      return 'jpg';
  }
}

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'assign';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'request':
        // ── [new] lender requests a rider to collect a payment ─────────────
        return await handleCollectionRequest(req);
      case 'assign':
        // ── [moved from functions/collections-assign/index.ts] ───────────
        return await handleCollectionAssign(req);
      case 'accept':
        // ── [moved from functions/collections-accept/index.ts] ───────────
        return await handleCollectionAccept(req);
      case 'decline':
        // ── [moved from functions/collections-decline/index.ts] ──────────
        return await handleCollectionDecline(req);
      case 'record':
        // ── [moved from functions/collections-record/index.ts] ───────────
        return await handleCollectionRecord(req);
      case 'upload-proof':
        // ── [moved from functions/collections-upload-proof/index.ts] ─────
        return await handleCollectionUploadProof(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('collections-manage error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [new] lender requests a rider to collect a payment ──────────────────────
async function handleCollectionRequest(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const roleCheck = requireRole(user, ROLES.LENDER);
  if (roleCheck) return roleCheck;

  const { loan_schedule_id, type = 'rider' } = await req.json();
  if (!loan_schedule_id) return errorResponse('loan_schedule_id is required', 400, 'VALIDATION_ERROR');
  if (!['rider', 'office'].includes(type)) {
    return errorResponse('type must be rider or office', 400, 'VALIDATION_ERROR');
  }

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const { data: schedule } = await db
    .from('loan_schedules')
    .select('id, loan_id, amount_due, due_date, loans(id, lender_id, status)')
    .eq('id', loan_schedule_id)
    .single();
  if (!schedule) return errorResponse('Schedule not found', 404, 'NOT_FOUND');

  const loan = embedAsObject(schedule.loans);
  if (!loan || loan.lender_id !== user.id) return errorResponse('Schedule not found', 404, 'NOT_FOUND');
  if (loan.status !== 'active') return errorResponse('Loan is not active', 400, 'INVALID_STATUS');

  const payment = await getSchedulePayment(db, loan_schedule_id);
  if (scheduleStatus(payment.amount_paid, Number(schedule.amount_due), schedule.due_date) === 'paid') {
    return errorResponse('Schedule already paid', 400, 'INVALID_STATUS');
  }

  const { data: active } = await db
    .from('collection_assignments')
    .select('id, status')
    .eq('loan_schedule_id', loan_schedule_id)
    .in('status', ['requested', 'assigned', 'accepted', 'in_progress'])
    .maybeSingle();
  if (active) return errorResponse('A collection is already in progress for this schedule', 409, 'INVALID_STATUS');

  const { data: assignment, error: insErr } = await db.from('collection_assignments').insert({
    loan_schedule_id,
    requested_by: user.id,
    collection_type: type,
    status: 'requested',
  }).select('id').single();
  if (insErr) return errorResponse('Failed to create collection request', 500, 'SERVER_ERROR');

  await writeAuditLog({
    performedBy: user.id,
    action: 'collection_request',
    tableName: 'collection_assignments',
    recordId: assignment.id,
    newValues: { loan_schedule_id, collection_type: type, status: 'requested' },
    ipAddress: ip,
  });

  if (type === 'office') {
    await notifyStaff({
      title: 'Office Payment Request',
      body: 'A lender will visit the office to pay an installment. Please prepare to record the payment.',
      type: 'office_payment_requested',
      referenceId: assignment.id,
      sentBy: user.id,
    });
  } else {
    await notifyStaff({
      title: 'New Collection Request',
      body: 'A lender has requested a rider to collect a payment. Please assign a rider.',
      type: 'collection_requested',
      referenceId: assignment.id,
      sentBy: user.id,
    });
  }

  return jsonResponse({ message: 'Collection request created', assignment_id: assignment.id }, 201);
}

// ── [moved from functions/collections-assign/index.ts] ──────────────────────
async function handleCollectionAssign(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;
  const { loan_schedule_id, rider_id, collection_schedule, notes, assignment_id } = await req.json();
  if ((!loan_schedule_id && !assignment_id) || !rider_id) {
    return errorResponse('loan_schedule_id (or assignment_id) and rider_id are required', 400, 'VALIDATION_ERROR');
  }
  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  // When a lender already requested a collection, assign a rider to that
  // existing request instead of creating a duplicate assignment.
  if (assignment_id) {
    const { data: existing } = await db.from('collection_assignments')
      .select('id, status, loan_schedule_id, requested_by')
      .eq('id', assignment_id).single();
    if (!existing) return errorResponse('Assignment not found', 404, 'NOT_FOUND');
    if (existing.status !== 'requested') return errorResponse('Assignment is not in requested status', 400, 'INVALID_STATUS');

    const { data: schedule } = await db.from('loan_schedules')
      .select('id, loan_id, amount_due, due_date, loans(status)')
      .eq('id', existing.loan_schedule_id).single();
    if (!schedule) return errorResponse('Schedule not found', 404, 'NOT_FOUND');
    if (embedAsObject(schedule?.loans)?.status !== 'active') return errorResponse('Loan must be active', 400, 'INVALID_STATUS');
    const payment = await getSchedulePayment(db, existing.loan_schedule_id);
    if (scheduleStatus(payment.amount_paid, Number(schedule.amount_due), schedule.due_date) === 'paid') {
      return errorResponse('Schedule already paid', 400, 'INVALID_STATUS');
    }

    const { data: rider } = await db.from('rider_profiles').select('is_available').eq('id', rider_id).single();
    if (!rider?.is_available) return errorResponse('Rider is not available', 400, 'VALIDATION_ERROR');

    const { error: updErr } = await db.from('collection_assignments').update({
      rider_id,
      assigned_by: user.id,
      collection_schedule: collection_schedule ?? null,
      collection_notes: notes ?? null,
      status: 'assigned',
    }).eq('id', assignment_id);
    if (updErr) return errorResponse('Failed to assign rider', 500, 'SERVER_ERROR');

    await writeAuditLog({ performedBy: user.id, action: 'collection_assign', tableName: 'collection_assignments', recordId: assignment_id, newValues: { rider_id, status: 'assigned' }, ipAddress: ip });
    await sendPushNotification({ userId: rider_id, title: 'New Collection Assignment', body: 'You have a new cash collection assignment. Please review and accept.', type: 'collection_assigned', referenceId: assignment_id });
    return jsonResponse({ message: 'Collection assigned', assignment_id }, 200);
  }

  const { data: schedule } = await db.from('loan_schedules').select('id, loan_id, amount_due, due_date, loans(status)').eq('id', loan_schedule_id).single();
  if (!schedule) return errorResponse('Schedule not found', 404, 'NOT_FOUND');
  if (embedAsObject(schedule?.loans)?.status !== 'active') return errorResponse('Loan must be active', 400, 'INVALID_STATUS');
  const payment = await getSchedulePayment(db, loan_schedule_id);
  if (scheduleStatus(payment.amount_paid, Number(schedule.amount_due), schedule.due_date) === 'paid') return errorResponse('Schedule already paid', 400, 'INVALID_STATUS');
  const { data: rider } = await db.from('rider_profiles').select('is_available').eq('id', rider_id).single();
  if (!rider?.is_available) return errorResponse('Rider is not available', 400, 'VALIDATION_ERROR');
  const { data: assignment, error: insErr } = await db.from('collection_assignments').insert({
    loan_schedule_id,
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
}

// ── [moved from functions/collections-accept/index.ts] ──────────────────────
async function handleCollectionAccept(req: Request) {
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
}

// ── [moved from functions/collections-decline/index.ts] ─────────────────────
async function handleCollectionDecline(req: Request) {
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
  await db.from('collection_assignments').update({ status: 'declined', response_at: new Date().toISOString(), collection_notes: reason ?? null }).eq('id', assignment_id);
  await writeAuditLog({ performedBy: user.id, action: 'collection_decline', tableName: 'collection_assignments', recordId: assignment_id, ipAddress: ip });
  if (assignment.assigned_by) await sendPushNotification({ userId: assignment.assigned_by, title: 'Collection Declined', body: 'The rider declined the collection assignment. Please reassign.', type: 'collection_declined', referenceId: assignment_id });
  return jsonResponse({ message: 'Assignment declined' });
}

// ── [moved from functions/collections-record/index.ts] ──────────────────────
async function handleCollectionRecord(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const roleCheck = requireRole(user, ROLES.RIDER);
  if (roleCheck) return roleCheck;

  const idempotencyKey = req.headers.get('x-idempotency-key');
  if (!idempotencyKey) return errorResponse('x-idempotency-key header required', 400, 'VALIDATION_ERROR');

  const { assignment_id, amount_collected, notes, latitude: _latitude, longitude: _longitude } = await req.json();
  if (!assignment_id || amount_collected === undefined) return errorResponse('assignment_id and amount_collected required', 400, 'VALIDATION_ERROR');
  if (amount_collected <= 0) return errorResponse('Amount must be positive', 400, 'VALIDATION_ERROR');

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const { data: existing } = await db.from('payments').select('id').eq('idempotency_key', idempotencyKey).maybeSingle();
  if (existing) return errorResponse('Duplicate request detected', 409, 'IDEMPOTENCY_CONFLICT');

  const { data: assignment } = await db.from('collection_assignments')
    .select('id, status, rider_id, loan_schedule_id, assigned_by, loan_schedule:loan_schedules(loan_id, loans(lender_id))')
    .eq('id', assignment_id).eq('rider_id', user.id).single();
  if (!assignment) return errorResponse('Assignment not found', 404, 'NOT_FOUND');
  if (!['accepted'].includes(assignment.status)) return errorResponse('Assignment must be accepted first', 400, 'INVALID_STATUS');

  const loanSchedule = embedAsObject(assignment?.loan_schedule);
  const loanId = loanSchedule?.loan_id;
  const loanData = embedAsObject(loanSchedule?.loans);
  const financials = await getLoanFinancials(db, loanId);
  if (!loanId || !loanData || !financials) return errorResponse('Loan not found', 404, 'NOT_FOUND');
  if (amount_collected > financials.outstanding_balance) return errorResponse('Amount exceeds outstanding balance', 400, 'VALIDATION_ERROR');

  const newBalance = Math.round((financials.outstanding_balance - amount_collected) * 100) / 100;

  const { data: payment, error: payErr } = await db.from('payments').insert({
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

  await db.from('loans').update({ ...(newBalance <= 0 ? { status: 'completed' } : {}) }).eq('id', loanId);
  await db.from('collection_assignments').update({ status: 'in_progress', completed_at: new Date().toISOString(), amount_collected }).eq('id', assignment_id);

  await writeAuditLog({ performedBy: user.id, action: 'collection_record', tableName: 'payments', recordId: payment.id, newValues: { amount: amount_collected, method: 'rider_collection' }, ipAddress: ip });
  await sendPushNotification({ userId: loanData.lender_id, title: 'Payment Collected', body: `Payment of ₱${amount_collected.toLocaleString()} has been collected. Remaining: ₱${newBalance.toLocaleString()}`, type: 'payment_collected', referenceId: payment.id });

  return jsonResponse({ message: 'Payment recorded', payment_id: payment.id, new_balance: newBalance }, 201);
}

// ── [moved from functions/collections-upload-proof/index.ts] ────────────────
async function handleCollectionUploadProof(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const roleCheck = requireRole(user, ROLES.RIDER);
  if (roleCheck) return roleCheck;

  const { assignment_id, proofs } = await req.json();
  if (!assignment_id || !Array.isArray(proofs) || proofs.length === 0) {
    return errorResponse('assignment_id and proofs[] required', 400, 'VALIDATION_ERROR');
  }
  if (!proofs.some((p) => p?.type === 'proof_photo')) {
    return errorResponse('At least one proof_photo is required', 400, 'VALIDATION_ERROR');
  }

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const { data: assignment } = await db
    .from('collection_assignments')
    .select('id, status, rider_id, proof_photo, borrower_signature, collection_photo')
    .eq('id', assignment_id)
    .eq('rider_id', user.id)
    .single();
  if (!assignment) return errorResponse('Assignment not found', 404, 'NOT_FOUND');
  if (!['accepted', 'in_progress'].includes(assignment.status)) {
    return errorResponse('Invalid assignment status', 400, 'INVALID_STATUS');
  }

  const updates: Record<string, string> = {};
  for (const proof of proofs) {
    const type = proof?.type as string;
    const column = COLUMN_BY_TYPE[type];
    if (!column || !proof.content_base64) continue;

    const ext = extFromMime(proof.mime_type);
    const path = `${assignment_id}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
    const bytes = decodeBase64(proof.content_base64);

    const { error: uploadError } = await db.storage
      .from(BUCKET)
      .upload(path, bytes, { contentType: proof.mime_type ?? 'image/jpeg', upsert: true });

    if (uploadError) {
      console.warn('storage upload failed, falling back to data uri:', uploadError.message);
      const mime = proof.mime_type ?? 'image/jpeg';
      updates[column] = `data:${mime};base64,${proof.content_base64}`;
    } else {
      const { data: signedUrl } = await db.storage.from(BUCKET).createSignedUrl(path, 3600 * 24 * 7);
      updates[column] = signedUrl?.signedUrl ?? path;
    }
  }

  if (Object.keys(updates).length === 0) {
    return errorResponse('No valid proofs provided', 400, 'VALIDATION_ERROR');
  }

  await db.from('collection_assignments').update({
    ...updates,
    status: 'completed',
    completed_at: new Date().toISOString(),
  }).eq('id', assignment_id);

  await writeAuditLog({
    performedBy: user.id,
    action: 'collection_upload_proof',
    tableName: 'collection_assignments',
    recordId: assignment_id,
    newValues: { status: 'completed' },
    ipAddress: ip,
  });

  return jsonResponse({ message: 'Proof uploaded, assignment completed' });
}