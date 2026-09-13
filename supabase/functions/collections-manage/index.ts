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
import { nowManilaISO } from '../_shared/timezone.ts';
import { ensureLoanSchedulesIfMissing } from '../_shared/loan_schedules.ts';
import {
  getSchedulePayment,
  scheduleStatus,
  getLoanFinancials,
  allocatePayment,
} from '../_shared/loan_financials.ts';

// ── [moved from collections-upload-proof] ───────────────────────────────────
const BUCKET = 'collection-proofs';

// The proof bucket may not exist in a fresh project. Without this guard every
// upload fails, the old data-URI fallback overflows the VARCHAR(255) proof
// columns, and the completion UPDATE silently no-ops — leaving assignments
// stuck in 'in_progress' while the rider sees "success".
async function ensureProofBucket(db: ReturnType<typeof getAdminClient>): Promise<void> {
  const { data: buckets } = await db.storage.listBuckets();
  if (buckets?.some((b) => b.name === BUCKET)) return;
  await db.storage.createBucket(BUCKET, { public: false, fileSizeLimit: '10MB' });
}

// ── [moved from collections-upload-proof] ───────────────────────────────────
const COLUMN_BY_TYPE: Record<string, string> = {
  proof_photo: 'proof_photo',
  scene_photo: 'collection_photo',
  signature: 'borrower_signature',
};

// ── Verified-payment lookup (record + upload-proof) ─────────────────────────
//
// Ang guard ng `fn=upload-proof` ay naghahanap ng verified na payment na
// naka-link sa assignment (`payments.collection_assignment_id`). Kapag hindi ito
// natagpuan, 409 PAYMENT_NOT_RECORDED ang isinasagot — at doon na-stuck ang
// rider kahit naitala naman ang cash.
//
// Fallback: kung walang naka-link na payment PERO may verified na
// `rider_collection` payment ang PAREHONG rider para sa loan_schedule ng
// assignment na ito (na hindi pa naka-link sa kahit anong assignment), iyon na
// ang ginagamit at **ini-repair** ang link. Ito ang sumasagip sa mga lumang row
// na nawalan ng link, at pumipigil din sa doble-record (dahil hindi na
// mag-iinsert muli ang `fn=record`).
async function findRecordedPayment(
  db: ReturnType<typeof getAdminClient>,
  assignmentId: string,
  loanScheduleId: string | null,
  riderUserId: string,
): Promise<{ id: string } | null> {
  const { data: linked } = await db
    .from('payments')
    .select('id, loan_schedule_id')
    .eq('collection_assignment_id', assignmentId)
    .eq('status', 'verified')
    .limit(1)
    .maybeSingle();
  if (linked) {
    await linkPaymentToSchedule(db, linked.id, linked.loan_schedule_id, loanScheduleId);
    return { id: linked.id };
  }

  if (!loanScheduleId) return null;
  const { data: unlinked } = await db
    .from('payments')
    .select('id')
    .eq('loan_schedule_id', loanScheduleId)
    .eq('payment_method', 'rider_collection')
    .eq('status', 'verified')
    .eq('recorded_by', riderUserId)
    .is('collection_assignment_id', null)
    .limit(1)
    .maybeSingle();
  if (!unlinked) return null;

  const { error: linkErr } = await db
    .from('payments')
    .update({ collection_assignment_id: assignmentId })
    .eq('id', unlinked.id);
  if (linkErr) {
    console.error('payment link repair failed:', linkErr.message);
  } else {
    console.log(`[collections] repaired payment ${unlinked.id} → assignment ${assignmentId}`);
  }
  return unlinked;
}

// Kung ang verified payment ay WALANG `loan_schedule_id` (o naka-NULL), i-link
// ito sa schedule ng assignment. Ang per-schedule reads (`v_loan_schedules`,
// `getSchedulePayment`) ay sumusunod sa link na iyon — kung NULL, mukhang hindi
// pa bayad ang installment kahit naitala na ang pera. (Ang kabuuang outstanding
// balance ay sumasalo na ng `collection_assignment_id` link sa
// `sumVerifiedPaymentsByLoan`, pero dapat pareho ang nakikita sa lahat ng
// screen.)
async function linkPaymentToSchedule(
  db: ReturnType<typeof getAdminClient>,
  paymentId: string,
  currentScheduleId: string | null | undefined,
  assignmentScheduleId: string | null,
): Promise<void> {
  if (!paymentId || !assignmentScheduleId || currentScheduleId) return;
  const { error } = await db
    .from('payments')
    .update({ loan_schedule_id: assignmentScheduleId })
    .eq('id', paymentId)
    .is('loan_schedule_id', null);
  if (error) {
    console.error('[collections] payment schedule link repair failed:', error.message);
  } else {
    console.log(
      `[collections] repaired payment ${paymentId} → schedule ${assignmentScheduleId}`,
    );
  }
}

// ── [moved from collections-upload-proof] ───────────────────────────────────
function decodeBase64(content: string): Uint8Array {
  const binary = atob(content);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

// ── Background side effects ─────────────────────────────────────────────────
// EdgeRuntime.waitUntil keeps the isolate alive AFTER the HTTP response is
// sent, so slow work (audit log insert, FCM fan-out to every staff device)
// can never delay the reply the client is waiting for. Without this the
// lender's "Pay via Cash on Delivery" tap could exceed the client's 30s Dio
// receiveTimeout: the app then showed the generic "Request Not Sent" dialog
// even though the collection_assignments row had already been inserted.
function runInBackground(task: Promise<unknown>): void {
  const runtime = (globalThis as {
    EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void };
  }).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(task);
    return;
  }
  // No waitUntil hook (plain `deno run` / older runtime) — still never await it.
  task.catch((err) => console.error('background task failed:', err));
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

  const { loan_schedule_id, type = 'rider', amount } = await req.json();
  if (!loan_schedule_id) return errorResponse('loan_schedule_id is required', 400, 'VALIDATION_ERROR');
  if (!['rider', 'office'].includes(type)) {
    return errorResponse('type must be rider or office', 400, 'VALIDATION_ERROR');
  }
  // amount is flexible: lender can pay any positive amount up to outstanding_balance
  // If omitted, system will default to the schedule's remaining amount on the client,
  // but we also support explicit amount here for business-rule enforcement.
  let requestedAmount: number | null = null;
  if (amount !== undefined && amount !== null && amount !== '') {
    requestedAmount = Number(amount);
    if (!Number.isFinite(requestedAmount) || requestedAmount <= 0) {
      return errorResponse('Amount must be a positive number', 400, 'VALIDATION_ERROR');
    }
    if (requestedAmount > 10000000) {
      return errorResponse('Amount too large', 400, 'VALIDATION_ERROR');
    }
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
  // 'overdue' loans stay collectable — that is exactly when a lender needs a
  // rider/office collection. Only terminal states are rejected.
  if (!['active', 'overdue'].includes(loan.status)) {
    return errorResponse('Loan is not in a payable status', 400, 'INVALID_STATUS');
  }

  const payment = await getSchedulePayment(db, loan_schedule_id);
  if (scheduleStatus(payment.amount_paid, Number(schedule.amount_due), schedule.due_date) === 'paid') {
    return errorResponse('Schedule already paid', 400, 'INVALID_STATUS');
  }

  // Validate requested amount against outstanding_balance if provided
  if (requestedAmount !== null) {
    const financials = await getLoanFinancials(db, loan.id as string);
    if (!financials) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (requestedAmount > Number(financials.outstanding_balance) + 0.01) {
      return errorResponse(`Amount ₱${requestedAmount.toLocaleString()} exceeds outstanding balance ₱${Number(financials.outstanding_balance).toLocaleString()}`, 400, 'VALIDATION_ERROR');
    }
    const remainingForSchedule = Math.max(0, Number(schedule.amount_due) - payment.amount_paid);
    // Allow paying less than remaining (partial) or more (advance to next installments) — just warn if way beyond
    // But if amount is less than a minimal threshold (e.g., 100 pesos), require at least 100 to avoid dust payments
    if (requestedAmount < 1) {
      return errorResponse('Amount must be at least ₱1', 400, 'VALIDATION_ERROR');
    }
  }

  const { data: active } = await db
    .from('collection_assignments')
    .select('id, status, requested_by, created_at')
    .eq('loan_schedule_id', loan_schedule_id)
    .in('status', ['requested', 'assigned', 'accepted', 'in_progress'])
    .maybeSingle();
  if (active) {
    // Idempotent replay: a double-tap or client retry from the same lender must
    // not fail — it would otherwise poison the schedule with an unanswerable
    // 409 since there is no cancel flow yet.
    if (active.status === 'requested' && active.requested_by === user.id) {
      // Stale-request expiry: a request nobody acted on for 48h must not block
      // the schedule forever. Expire it and fall through to a fresh request.
      const ageHours = (Date.now() - new Date(active.created_at).getTime()) / 3_600_000;
      if (ageHours < 48) {
        return jsonResponse({ message: 'You have already pending payment', assignment_id: active.id }, 200);
      }
      await db.from('collection_assignments')
        .update({ status: 'failed', collection_notes: 'expired: no action within 48h' })
        .eq('id', active.id)
        .eq('status', 'requested');
    } else {
      return errorResponse('You have already pending payment', 409, 'ALREADY_IN_PROGRESS');
    }
  }

  const { data: assignment, error: insErr } = await db.from('collection_assignments').insert({
    loan_schedule_id,
    requested_by: user.id,
    requested_at: nowManilaISO(),
    collection_type: type,
    requested_amount: requestedAmount,
    status: 'requested',
    // Explicit NULL: the column default for status_id is the ASSIGNED status
    // UUID, and trg_sync_collection_assignments_lookup_ids overwrites
    // `status` from `status_id` on INSERT. Without this the row would be
    // silently flipped to 'assigned' with no rider, violating
    // collection_assignments_rider_required_unless_unassigned_request
    // (23514) and failing the lender's request with "Request Not Sent".
    // Passing NULL makes the trigger resolve status_id from `status`
    // ('requested') instead of applying the column default.
    status_id: null,
  }).select('id').single();
  if (insErr) {
    // Lost a race against a concurrent identical request (unique partial index
    // uq_collection_assignments_requested_schedule) → treat as idempotent success.
    if ((insErr as { code?: string }).code === '23505') {
      const { data: existing } = await db.from('collection_assignments')
        .select('id')
        .eq('loan_schedule_id', loan_schedule_id)
        .eq('status', 'requested')
        .maybeSingle();
      if (existing) return jsonResponse({ message: 'You have already pending payment', assignment_id: existing.id }, 200);
    }
    console.error('collection request insert failed:', insErr);
    return errorResponse('Failed to create collection request', 500, 'SERVER_ERROR');
  }

  // ── Respond FIRST, then run the audit + staff notifications in the ────────
  // background. The lender's app gives this call 30s; notifyStaff pushes FCM
  // to every active staff device (one external HTTP request each), which
  // regularly blew past that budget and produced a false "Request Not Sent"
  // dialog for a request that had in fact been created.
  runInBackground((async () => {
    try {
      await writeAuditLog({
        performedBy: user.id,
        action: 'collection_request',
        tableName: 'collection_assignments',
        recordId: assignment.id,
        newValues: { loan_schedule_id, collection_type: type, requested_amount: requestedAmount, status: 'requested' },
        ipAddress: ip,
      });
    } catch (e) {
      console.error('writeAuditLog failed (non-fatal):', e);
    }

    try {
      const amountLabel = requestedAmount ? ` of ₱${requestedAmount.toLocaleString()}` : '';
      if (type === 'office') {
        await notifyStaff({
          title: 'Office Payment Request',
          body: `A lender will visit the office to pay${amountLabel}. Please prepare to record the payment.`,
          type: 'office_payment_requested',
          referenceId: assignment.id,
          sentBy: user.id,
        });
      } else {
        await notifyStaff({
          title: 'New Collection Request',
          body: `A lender has requested a rider to collect${amountLabel}. Please assign a rider.`,
          type: 'collection_requested',
          referenceId: assignment.id,
          sentBy: user.id,
        });
      }
    } catch (e) {
      console.error('notifyStaff failed (non-fatal):', e);
    }
  })());

  return jsonResponse({ message: 'Collection request created', assignment_id: assignment.id, requested_amount: requestedAmount }, 201);
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
    if (!['active', 'overdue'].includes((embedAsObject(schedule?.loans)?.status) ?? '')) return errorResponse('Loan is not in a payable status', 400, 'INVALID_STATUS');
    const payment = await getSchedulePayment(db, existing.loan_schedule_id);
    if (scheduleStatus(payment.amount_paid, Number(schedule.amount_due), schedule.due_date) === 'paid') {
      return errorResponse('Schedule already paid', 400, 'INVALID_STATUS');
    }

    const { data: rider } = await db.from('rider_profiles').select('is_available').eq('id', rider_id).single();
    if (!rider?.is_available) return errorResponse('Rider is not available', 400, 'VALIDATION_ERROR');

    const { error: updErr } = await db.from('collection_assignments').update({
      rider_id,
      assigned_by: user.id,
      assigned_at: nowManilaISO(),
      collection_schedule: collection_schedule ?? null,
      collection_notes: notes ?? null,
      status: 'assigned',
    }).eq('id', assignment_id);
    if (updErr) return errorResponse('Failed to assign rider', 500, 'SERVER_ERROR');

    await writeAuditLog({ performedBy: user.id, action: 'collection_assign', tableName: 'collection_assignments', recordId: assignment_id, newValues: { rider_id, status: 'assigned' }, ipAddress: ip });
    await sendPushNotification({ userId: rider_id, title: 'New Cash on Delivery Collection Task', body: 'Hello! You have a new Cash on Delivery collection task. Please review the details and accept it promptly.', type: 'collection_assigned', referenceId: assignment_id });
    return jsonResponse({ message: 'Collection assigned', assignment_id }, 200);
  }

  const { data: schedule } = await db.from('loan_schedules').select('id, loan_id, amount_due, due_date, loans(status)').eq('id', loan_schedule_id).single();
  if (!schedule) return errorResponse('Schedule not found', 404, 'NOT_FOUND');
  if (!['active', 'overdue'].includes((embedAsObject(schedule?.loans)?.status) ?? '')) return errorResponse('Loan is not in a payable status', 400, 'INVALID_STATUS');
  const payment = await getSchedulePayment(db, loan_schedule_id);
  if (scheduleStatus(payment.amount_paid, Number(schedule.amount_due), schedule.due_date) === 'paid') return errorResponse('Schedule already paid', 400, 'INVALID_STATUS');
  const { data: rider } = await db.from('rider_profiles').select('is_available').eq('id', rider_id).single();
  if (!rider?.is_available) return errorResponse('Rider is not available', 400, 'VALIDATION_ERROR');
  const { data: assignment, error: insErr } = await db.from('collection_assignments').insert({
    loan_schedule_id,
    rider_id,
    assigned_by: user.id,
    assigned_at: nowManilaISO(),
    collection_schedule: collection_schedule ?? null,
    collection_notes: notes ?? null,
    status: 'assigned',
  }).select('id').single();
  if (insErr) return errorResponse('Failed to create assignment', 500, 'SERVER_ERROR');
  await writeAuditLog({ performedBy: user.id, action: 'collection_assign', tableName: 'collection_assignments', recordId: assignment.id, ipAddress: ip });
  await sendPushNotification({ userId: rider_id, title: 'New Cash on Delivery Collection Task', body: 'Hello! You have a new Cash on Delivery collection task. Please review the details and accept it promptly.', type: 'collection_assigned', referenceId: assignment.id });
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
  await db.from('collection_assignments').update({ status: 'accepted', response_at: nowManilaISO() }).eq('id', assignment_id);
  await writeAuditLog({ performedBy: user.id, action: 'collection_accept', tableName: 'collection_assignments', recordId: assignment_id, ipAddress: ip });
  if (assignment.assigned_by) await sendPushNotification({ userId: assignment.assigned_by, title: 'Collection Accepted by Rider', body: 'The rider has accepted the Cash on Delivery collection task and will proceed.', type: 'collection_accepted', referenceId: assignment_id });
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
  await db.from('collection_assignments').update({ status: 'declined', response_at: nowManilaISO(), collection_notes: reason ?? null }).eq('id', assignment_id);
  await writeAuditLog({ performedBy: user.id, action: 'collection_decline', tableName: 'collection_assignments', recordId: assignment_id, ipAddress: ip });
  if (assignment.assigned_by) await sendPushNotification({ userId: assignment.assigned_by, title: 'Collection Declined by Rider', body: 'The rider has declined the Cash on Delivery collection task. Please assign a new rider.', type: 'collection_declined', referenceId: assignment_id });
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
    .select('id, status, rider_id, loan_schedule_id, assigned_by, amount_collected, loan_schedule:loan_schedules(loan_id, loans(lender_id))')
    .eq('id', assignment_id).eq('rider_id', user.id).single();
  if (!assignment) return errorResponse('Assignment not found', 404, 'NOT_FOUND');

  // Idempotent: kung may verified payment na para sa assignment na ito, huwag
  // nang mag-insert muli — success (200) na agad para makatuloy ang client sa
  // proof upload. Kailangan ito dahil laging sumusubok mag-record ang client
  // bago mag-upload ng proof (para hindi ma-stuck ang rider kapag nag-retry).
  const alreadyRecorded = await findRecordedPayment(
    db,
    assignment_id,
    assignment.loan_schedule_id,
    user.id,
  );
  if (alreadyRecorded) {
    // Huwag nang mag-insert muli (magdodoble ang ibabawas sa loan).
    //
    // PERO ang `amount_collected` ay dapat LAGING tugma sa AKTWAL na verified
    // payments ng assignment na ito — hindi sa halagang ipinasa ng client.
    // Dati, ang value mula sa request ang isinusulat dito, kaya may pagkakataon
    // (hal. nauna nang nag-record na may ibang halaga, o naayos ang payment sa
    // staff side) na ang nakikita ng Head Manager / Employee na "Amount
    // Collected" ay iba sa aktwal na nabawas sa loan — ang balance ay DERIVED
    // mula sa payments, kaya hindi sila dapat magkahiwalay.
    const { data: paymentRows } = await db
      .from('payments')
      .select('amount')
      .eq('collection_assignment_id', assignment_id)
      .eq('status', 'verified');
    const recordedSum =
      Math.round((paymentRows ?? []).reduce((s, p) => s + Number(p.amount), 0) * 100) / 100;
    const storedAmount =
      assignment.amount_collected === null || assignment.amount_collected === undefined
        ? null
        : Number(assignment.amount_collected);

    const patch: Record<string, unknown> = {};
    if (storedAmount === null || Math.abs(storedAmount - recordedSum) > 0.005) {
      patch.amount_collected = recordedSum;
    }
    // Huwag ibaba ang `completed` pabalik sa `in_progress`.
    if (assignment.status !== 'in_progress' && assignment.status !== 'completed') {
      patch.status = 'in_progress';
    }
    if (Object.keys(patch).length > 0) {
      await db.from('collection_assignments').update(patch).eq('id', assignment_id);
      console.warn('[collections] record idempotent — inayos ang amount_collected', {
        assignmentId: assignment_id,
        storedAmount,
        recordedSum,
        patch,
      });
    }
    return jsonResponse({
      message: 'Payment already recorded',
      payment_id: alreadyRecorded.id,
      amount_collected: recordedSum,
    }, 200);
  }

  // `in_progress` ay pinapayagan para maka-recover ang rider kapag naiwang
  // in_progress ang assignment pero wala nang verified payment (hal. na-reverse
  // ang payment sa HM side). Kung may verified payment pa, nahuli na iyon sa
  // itaas at hindi na aabot dito.
  if (!['accepted', 'in_progress'].includes(assignment.status)) {
    return errorResponse('Assignment must be accepted first', 400, 'INVALID_STATUS');
  }

  const recorded = await recordRiderCollectionPayment({
    db,
    riderUserId: user.id,
    assignment,
    amount: Number(amount_collected),
    notes,
    idempotencyKey,
    ip,
  });
  if (!recorded.ok) {
    return errorResponse(
      recorded.message ?? 'Failed to record payment',
      recorded.status ?? 500,
      recorded.code ?? 'SERVER_ERROR',
    );
  }

  return jsonResponse({
    message: 'Payment recorded',
    payment_id: recorded.paymentId,
    new_balance: recorded.newBalance,
  }, 201);
}

// ── Verified-payment recording core (fn=record AT fn=upload-proof) ─────────
//
// Business rule: hindi maaaring maging `completed` ang isang koleksyon nang
// walang verified payment — ang loan balance ay DERIVED mula sa payments, kaya
// kung walang payment, bababa ang status pero HINDI bababa ang balanse ng
// lender (at may "Payment Received" push pa).
//
// Isang lugar lang ang logic na ito para magamit ng dalawang endpoint:
//   * `fn=record`        — normal na hakbang ng rider (Step 3 submit)
//   * `fn=upload-proof`  — kapag tumawag ng proof ang rider na WALA pang
//     verified payment (hal. na-reverse sa HM side, o na-skip ang record
//     dahil lumang build), DITO NA RIN itinatala ang amount sa halip na
//     ibalik ang paulit-ulit na 409 PAYMENT_NOT_RECORDED na parati nang
//     nagpapa-stuck sa rider ("in_progress" kahit naka-submit na).
interface RecordCoreResult {
  ok: boolean;
  paymentId?: string;
  newBalance?: number;
  message?: string;
  status?: number;
  code?: string;
}

async function recordRiderCollectionPayment(opts: {
  db: ReturnType<typeof getAdminClient>;
  riderUserId: string;
  // deno-lint-ignore no-explicit-any
  assignment: Record<string, any>;
  amount: number;
  notes?: string | null;
  idempotencyKey: string;
  ip: string;
}): Promise<RecordCoreResult> {
  const { db, riderUserId, assignment, amount, notes, idempotencyKey, ip } = opts;
  const assignmentId = String(assignment.id);

  const loanSchedule = embedAsObject(assignment?.loan_schedule);
  const loanId = loanSchedule?.loan_id;
  const loanData = embedAsObject(loanSchedule?.loans);
  const financials = await getLoanFinancials(db, loanId);
  if (!loanId || !loanData || !financials) {
    return { ok: false, message: 'Loan not found', status: 404, code: 'NOT_FOUND' };
  }
  if (amount > financials.outstanding_balance) {
    return {
      ok: false,
      message: 'Amount exceeds outstanding balance',
      status: 400,
      code: 'VALIDATION_ERROR',
    };
  }

  const newBalance = Math.round((financials.outstanding_balance - amount) * 100) / 100;

  // Allocate the collected amount across unpaid installments (oldest first).
  // Amounts beyond the current installment roll forward to the next ones so a
  // lender can advance-pay upcoming installments in a single collection.
  let allocations = await allocatePayment(db, loanId, amount);
  if (allocations.length === 0) {
    // Safety net: ang schedule ay ginagawa sa pag-activate ng loan. Kung
    // na-miss iyon (lumang data / bagong activation path), gawin na rito ang
    // schedule base sa ngayon at subukan muli — hindi dapat ma-stuck ang
    // koleksyon sa "No unpaid installments" dahil lang walang rows.
    if (await ensureLoanSchedulesIfMissing(db, loanId)) {
      allocations = await allocatePayment(db, loanId, amount);
    }
  }
  if (allocations.length === 0) {
    return {
      ok: false,
      message: 'No unpaid installments to apply the payment to',
      status: 409,
      code: 'INVALID_STATUS',
    };
  }

  const paymentRows = allocations.map((a, i) => ({
    loan_schedule_id: a.loan_schedule_id,
    amount: a.amount,
    payment_method: 'rider_collection',
    status: 'verified',
    recorded_by: riderUserId,
    collection_assignment_id: assignmentId,
    notes: notes ?? null,
    paid_at: nowManilaISO(),
    idempotency_key: allocations.length > 1 ? `${idempotencyKey}-${i + 1}` : idempotencyKey,
  }));

  const { data: payments, error: payErr } = await db
    .from('payments')
    .insert(paymentRows)
    .select('id');
  if (payErr || !payments || payments.length === 0) {
    console.error('payment insert failed:', payErr);
    return { ok: false, message: 'Failed to record payment', status: 500, code: 'SERVER_ERROR' };
  }

  if (newBalance <= 0) {
    await db.from('loans').update({ status: 'completed' }).eq('id', loanId);
  }
  // Business rule: ang `completed_at` ay para LANG sa tunay na natapos na
  // koleksyon (status = 'completed', naisagawa ng `fn=upload-proof`). Dito sa
  // record, `in_progress` + `amount_collected` lang ang isinusulat.
  await db
    .from('collection_assignments')
    .update({ status: 'in_progress', amount_collected: amount })
    .eq('id', assignmentId);

  await writeAuditLog({
    performedBy: riderUserId,
    action: 'collection_record',
    tableName: 'payments',
    recordId: payments[0].id,
    newValues: { amount, method: 'rider_collection' },
    ipAddress: ip,
  });
  await sendPushNotification({
    userId: loanData.lender_id,
    title: 'Payment Received',
    body: `Hello! Your payment of ₱${amount.toLocaleString()} has been successfully collected. Your remaining balance is ₱${newBalance.toLocaleString()}. Thank you!`,
    type: 'payment_collected',
    referenceId: payments[0].id,
  });

  return { ok: true, paymentId: payments[0].id, newBalance };
}

// ── [moved from functions/collections-upload-proof/index.ts] ────────────────
async function handleCollectionUploadProof(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const roleCheck = requireRole(user, ROLES.RIDER);
  if (roleCheck) return roleCheck;

  const {
    assignment_id,
    proofs,
    // Opsyonal: kapag WALA pang verified payment, ito ang amount na itatala ng
    // upload-proof mismo (self-heal). Ipinapasa ito ng rider app (ang amount na
    // nakalagay/na-validate sa Step 1–3).
    amount_collected: bodyAmount,
    notes: bodyNotes,
  } = await req.json();
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
    .select('id, status, rider_id, loan_schedule_id, amount_collected, proof_photo, borrower_signature, collection_photo, loan_schedule:loan_schedules(loan_id, loans(lender_id))')
    .eq('id', assignment_id)
    .eq('rider_id', user.id)
    .single();
  if (!assignment) return errorResponse('Assignment not found', 404, 'NOT_FOUND');
  if (!['accepted', 'in_progress'].includes(assignment.status)) {
    return errorResponse('Invalid assignment status', 400, 'INVALID_STATUS');
  }

  // The collected cash must be recorded as a verified payment BEFORE the
  // collection can be completed. Without this guard a rider can skip the
  // "Record Collection" step: the assignment completes and the office receives
  // the cash, but no payment row exists so the loan balance never decreases.
  let recordedPayment = await findRecordedPayment(
    db,
    assignment_id,
    assignment.loan_schedule_id,
    user.id,
  );
  if (!recordedPayment) {
    // ── Self-heal: itala na rito mismo ang cash ────────────────────────────
    // Dati, 409 PAYMENT_NOT_RECORDED ang isinasagot dito — at iyon ang paulit-
    // ulit na error ng rider ("Record the collected amount first before
    // uploading proof") kahit naka-lagay na ang amount sa app (hal. na-reverse
    // ang payment sa HM side, o na-skip ang record ng lumang build). Naiiwan
    // tuloy ang koleksyon sa `in_progress` forever.
    //
    // Ngayon: kung may amount (mula sa request o sa assignment), DITO NA RIN
    // itinatala ito (verified payment + `in_progress`) bago mag-upload ng proof
    // — kaya hindi na maaaring ma-stuck, at hindi rin mabababa ang status nang
    // hindi bumababa ang balanse ng loan.
    const amount = Number(bodyAmount ?? assignment.amount_collected ?? 0);
    if (!Number.isFinite(amount) || amount <= 0) {
      return errorResponse(
        'Record the collected amount first before uploading proof',
        409,
        'PAYMENT_NOT_RECORDED',
      );
    }
    console.warn(
      '[collections] upload-proof: walang verified payment — nire-record na rito ang amount',
      { assignmentId: assignment_id, amount },
    );
    const recorded = await recordRiderCollectionPayment({
      db,
      riderUserId: user.id,
      assignment,
      amount,
      notes: typeof bodyNotes === 'string' ? bodyNotes : null,
      idempotencyKey: `proof-${assignment_id}-${Date.now()}`,
      ip,
    });
    if (!recorded.ok) {
      return errorResponse(
        recorded.message ?? 'Failed to record payment',
        recorded.status ?? 500,
        recorded.code ?? 'SERVER_ERROR',
      );
    }
    recordedPayment = { id: recorded.paymentId ?? '' };
  }

  const updates: Record<string, string> = {};
  const failed: string[] = [];
  await ensureProofBucket(db);

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
      // Never fall back to inline data URIs: the proof columns are
      // VARCHAR(255) and a base64 image can never fit — the overflow made the
      // completion UPDATE fail silently while the rider was told "success".
      console.error(`storage upload failed for ${type}:`, uploadError.message);
      failed.push(type);
      continue;
    }
    const { data: signedUrl } = await db.storage.from(BUCKET).createSignedUrl(path, 3600 * 24 * 7);
    // Store the STORAGE PATH, not the signed URL: signed URLs embed a JWT and
    // exceed VARCHAR(255) (now TEXT), which historically made every completion
    // UPDATE fail. Views sign URLs on read so they are always fresh.
    updates[column] = path;
  }

  if (Object.keys(updates).length === 0) {
    return errorResponse(
      `Proof storage failed (${failed.join(', ') || 'no valid proofs'}). Please try again.`,
      502,
      'PROOF_UPLOAD_FAILED',
    );
  }

  // Isama ang `amount_collected` sa completion update. Dapat laging tugma ang
  // nakasulat na amount sa AKTWAL na verified payments ng assignment (ang loan
  // balance ay derived mula sa payments) — kung hindi, may koleksyong
  // `completed` na walang nakatalang halaga ("hindi na-save ang amount").
  const { data: payRows } = await db
    .from('payments')
    .select('amount')
    .eq('collection_assignment_id', assignment_id)
    .eq('status', 'verified');
  const recordedSum = Math.round(
    (payRows ?? []).reduce((s: number, p: { amount: string | number }) => s + Number(p.amount), 0) * 100,
  ) / 100;
  const completionPatch: Record<string, unknown> = {
    ...updates,
    status: 'completed',
    completed_at: nowManilaISO(),
  };
  if (recordedSum > 0) completionPatch.amount_collected = recordedSum;

  const { error: updErr } = await db.from('collection_assignments').update(completionPatch).eq('id', assignment_id);
  if (updErr) {
    console.error('assignment completion update failed:', updErr);
    return errorResponse('Failed to mark collection completed', 500, 'SERVER_ERROR');
  }

  await writeAuditLog({
    performedBy: user.id,
    action: 'collection_upload_proof',
    tableName: 'collection_assignments',
    recordId: assignment_id,
    newValues: { status: 'completed', amount_collected: recordedSum || null, failed_proofs: failed },
    ipAddress: ip,
  });

  // Ang `status` ay isinasauli sa client para hindi na kailangan ng karagdagang
  // `get` (may kasamang pag-sign ng 3 proof URL, mabigat) para kumpirmahin ang
  // completion — pinapabilis nito nang malaki ang Submit sa Step 3.
  return jsonResponse({
    message: failed.length > 0
      ? 'Collection completed, but some proofs failed to upload'
      : 'Proof uploaded, assignment completed',
    status: 'completed',
    amount_collected: recordedSum || null,
    failed_proofs: failed,
  });
}