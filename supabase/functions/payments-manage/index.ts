// supabase/functions/payments-manage/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   payments-record-office  →  ?fn=record-office
//   payments-reverse        →  ?fn=reverse
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeString } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { getPaymentLoanId, getLoanFinancials, allocatePayment } from '../_shared/loan_financials.ts';
import { ensureLoanSchedulesIfMissing } from '../_shared/loan_schedules.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'record-office';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'record-office':
        // ── [moved from functions/payments-record-office/index.ts] ──────
        return await handleRecordOffice(req);
      case 'reverse':
        // ── [moved from functions/payments-reverse/index.ts] ────────────
        return await handleReverse(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('payments-manage error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/payments-record-office/index.ts] ───────────────────
async function handleRecordOffice(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const idempotencyKey = req.headers.get('x-idempotency-key');
  if (!idempotencyKey) return errorResponse('Idempotency key required', 400, 'VALIDATION_ERROR');

  const { loan_id, loan_schedule_id, amount, notes, assignment_id } = await req.json();

  if (!loan_id || !loan_schedule_id || !amount) {
    return errorResponse('loan_id, loan_schedule_id, and amount are required', 400, 'VALIDATION_ERROR');
  }
  if (Number(amount) <= 0) return errorResponse('Amount must be positive', 400, 'VALIDATION_ERROR');

  const db = getAdminClient();

  const { data: existing } = await db
    .from('payments')
    .select('id')
    .eq('idempotency_key', idempotencyKey)
    .single();

  if (existing) return errorResponse('Duplicate payment detected', 409, 'IDEMPOTENCY_CONFLICT');

  const { data: loan } = await db
    .from('loans')
    .select('id, lender_id, status')
    .eq('id', loan_id)
    .single();

  if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
  if (!['active', 'overdue'].includes(loan.status)) {
    return errorResponse('Loan is not in payable status', 409, 'INVALID_STATUS');
  }

  const financials = await getLoanFinancials(db, loan_id);
  if (!financials) return errorResponse('Loan not found', 404, 'NOT_FOUND');
  if (Number(amount) > financials.outstanding_balance) {
    return errorResponse('Amount exceeds outstanding balance', 400, 'VALIDATION_ERROR');
  }

  const { data: schedule } = await db
    .from('loan_schedules')
    .select('id, amount_due, due_date')
    .eq('id', loan_schedule_id)
    .eq('loan_id', loan_id)
    .single();

  if (!schedule) return errorResponse('Schedule not found', 404, 'NOT_FOUND');

  // The recorded cash is allocated across unpaid installments: ang installment
  // na PININDOT ng staff (`loan_schedule_id`) ang UNANG binabayaran, tapos ang
  // natitirang halaga ay sa pinaka-lumang unpaid pa (oldest-first). Ito ang
  // nagpapa-PAID sa mismong row na binayaran — kung basta oldest-first, ang
  // pera ay mapupunta sa pinaka-lumang unpaid na installment at mananatiling
  // `pending` ang row na pinindot. Ang labis na halaga ay hindi kailanman
  // mapupunta sa bayad nang installment, kaya imposible ang doble.
  let allocations = await allocatePayment(
    db,
    loan_id,
    Number(amount),
    loan_schedule_id,
  );
  if (allocations.length === 0) {
    // Safety net: ang payment schedule ay ginagawa sa pag-activate ng loan.
    // Kung wala pa ito (hal. lumang data o na-miss na activation path), gawin
    // na rito base sa ngayon bago sumuko — hindi dapat harangan ng "No unpaid
    // installments" ang isang lehitimong bayad.
    if (await ensureLoanSchedulesIfMissing(db, loan_id)) {
      allocations = await allocatePayment(
        db,
        loan_id,
        Number(amount),
        loan_schedule_id,
      );
    }
  }
  if (allocations.length === 0) {
    return errorResponse('No unpaid installments remaining', 409, 'PAYMENT_ALREADY_MADE');
  }

  const paymentRows = allocations.map((a, i) => ({
    loan_schedule_id: a.loan_schedule_id,
    amount: a.amount,
    payment_method: 'office_cash',
    status: 'verified',
    // Explicit NULL — KRITIKAL: ang `payments.status_id` ay may DEFAULT na
    // PENDING status, at ang `sync_payments_lookup_ids` trigger ay nag-o-
    // overwrite ng `status` mula sa `status_id` kapag `status_id IS DISTINCT
    // FROM OLD.status_id` (NULL ito sa INSERT). Kung hindi ito ipapasa, ang
    // `verified` ay nagiging `pending` — kaya HINDI ito binibilang sa
    // `v_loan_schedules.amount_paid` (verified lang ang binibilang), hindi
    // bumababa ang balance, at mananatiling Pending ang installment.
    // Sa pagpasa ng NULL, ang `status` ('verified') ang pinagmumulan ng
    // `status_id` (parehong behavior sa alinmang bersyon ng trigger).
    status_id: null,
    recorded_by: authResult.id,
    idempotency_key: allocations.length > 1 ? `${idempotencyKey}-${i + 1}` : idempotencyKey,
    notes: notes ?? null,
    paid_at: new Date().toISOString(),
  }));

  const { data: insertedPayments, error: payErr } = await db
    .from('payments')
    .insert(paymentRows)
    .select();

  if (payErr || !insertedPayments || insertedPayments.length === 0) {
    console.error('payment insert failed:', payErr);
    return errorResponse('Failed to record payment', 500, 'SERVER_ERROR');
  }
  const payment = insertedPayments[0];

  // ── Isara ang collection request/assignment na natugunan na ng bayad ───────
  // Bayad na ang pera sa office, kaya dapat COLLECTED na ito: hindi na
  // kailangang mag-assign ng rider at hindi na dapat manatiling Requested ang
  // row sa Collections. Kung hindi isasara, mananatiling pending ang request
  // kahit PAID na ang installment.
  //
  // MAHALAGA — CHECK constraint
  // `collection_assignments_rider_required_unless_unassigned_request`:
  //   status IN ('requested','declined') OR (rider_id IS NOT NULL AND assigned_by IS NOT NULL)
  // Kaya imposibleng gawing 'completed' ang row na WALANG rider — tahimik itong
  // nabibigo. Ang tamang pang-sara ay:
  //   • may rider    → 'completed' (+ completed_at, required ng
  //                    `collection_assignments_completed_requires_completed_at`)
  //   • walang rider → 'declined' (+ response_at, tulad ng rider decline sa
  //                    collections-manage) — "turned down before assignment".
  // Ang 'declined' ay wala sa OPEN_COLLECTION_STATUSES ng collections-view,
  // kaya tuluyang nawawala ang row sa pending list.
  //
  // Ang PARTIAL na bayad ay HINDI nagpapasara — bukas pa ang natitirang utang
  // ng installment, kaya dapat pa ring makita ng staff ang request. (Maliban sa
  // partikular na request na pinindot ng staff, na natugunan na.)
  const OPEN_ASSIGNMENT_STATUSES = ['requested', 'assigned', 'accepted', 'in_progress', 'pending_approval'];
  const closedAt = new Date().toISOString();
  const scheduleIds = allocations.map((a) => a.loan_schedule_id);

  const { data: settledRows } = await db
    .from('v_loan_schedules')
    .select('id, amount_due, amount_paid')
    .in('id', scheduleIds);
  const collectedBySchedule = new Map<string, number>();
  for (const s of settledRows ?? []) {
    const collected = Number(s.amount_paid ?? 0);
    if (collected < Number(s.amount_due)) continue;
    collectedBySchedule.set(s.id, collected);
  }

  const { data: openAssignments } = await db
    .from('collection_assignments')
    .select('id, rider_id, assigned_by, loan_schedule_id')
    .in('status', OPEN_ASSIGNMENT_STATUSES)
    .in('loan_schedule_id', scheduleIds);

  type Closable = { rider_id: string | null; assigned_by: string | null; collected: number };
  const toClose = new Map<string, Closable>();
  for (const a of openAssignments ?? []) {
    const settled = collectedBySchedule.get(a.loan_schedule_id);
    if (settled === undefined && a.id !== assignment_id) continue;
    toClose.set(a.id, {
      rider_id: a.rider_id,
      assigned_by: a.assigned_by,
      collected: settled ?? Number(amount),
    });
  }
  // Ang partikular na request na pinindot ng staff ay natugunan na kahit partial.
  if (assignment_id && !toClose.has(assignment_id)) {
    const { data: chosen } = await db
      .from('collection_assignments')
      .select('id, rider_id, assigned_by, loan_schedule_id')
      .eq('id', assignment_id)
      .in('status', OPEN_ASSIGNMENT_STATUSES)
      .maybeSingle();
    if (chosen) {
      toClose.set(chosen.id, {
        rider_id: chosen.rider_id,
        assigned_by: chosen.assigned_by,
        collected: collectedBySchedule.get(chosen.loan_schedule_id) ?? Number(amount),
      });
    }
  }

  for (const [id, a] of toClose) {
    const patch = a.rider_id && a.assigned_by
      ? { status: 'completed', completed_at: closedAt, amount_collected: a.collected }
      : {
        status: 'declined',
        response_at: closedAt,
        amount_collected: a.collected,
        collection_notes: 'Paid in office — rider pickup no longer needed',
      };
    const { error: closeErr } = await db.from('collection_assignments').update(patch).eq('id', id);
    if (closeErr) console.error('failed to close collection assignment:', id, closeErr);
  }

  const newBalance = Math.max(0, Math.round((financials.outstanding_balance - Number(amount)) * 100) / 100);
  const loanStatus = newBalance <= 0 ? 'completed' : loan.status;

  await db.from('loans').update({
    status: loanStatus,
  }).eq('id', loan_id);

  await writeAuditLog({
    performedBy: authResult.id,
    action: 'payment_recorded',
    tableName: 'payments',
    recordId: payment.id,
    newValues: { amount: Number(amount), method: 'office_cash', loan_id },
    ipAddress: req.headers.get('x-forwarded-for') ?? undefined,
  });

  // Ang office payment ay dapat MALINAW sa lender na SA OFFICE siya nagbayad
  // (hindi rider collection, hindi GCash) — kaya binabanggit ang channel sa
  // title at body, tulad ng 'Office' na label ng `payment_method = office_cash`
  // sa app (`PaymentModel.methodLabel`).
  await sendPushNotification({
    userId: loan.lender_id,
    title: 'Paid in Office',
    body: `Your payment of ₱${Number(amount).toLocaleString()} was recorded at the office. Remaining balance: ₱${newBalance.toLocaleString()}`,
    type: 'payment_recorded',
    referenceId: payment.id,
  });

  return jsonResponse({
    payment_id: payment.id,
    amount: Number(amount),
    outstanding_balance: newBalance,
    loan_status: loanStatus,
    closed_assignments: toClose.size,
  }, 201);
}

// ── [moved from functions/payments-reverse/index.ts] ─────────────────────────
async function handleReverse(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const roleCheck = requireRole(user, ROLES.HEAD_MANAGER);
  if (roleCheck) return roleCheck;
  const { payment_id, reason } = await req.json();
  if (!payment_id || !reason) return errorResponse('payment_id and reason required', 400, 'VALIDATION_ERROR');
  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
  const { data: payment } = await db.from('payments').select('id, status, amount, loan_schedule_id, collection_assignment_id').eq('id', payment_id).single();
  if (!payment) return errorResponse('Payment not found', 404, 'NOT_FOUND');
  if (payment.status !== 'verified') return errorResponse('Only verified payments can be reversed', 400, 'INVALID_STATUS');
  await db.from('payments').update({ status: 'reversed' }).eq('id', payment_id);
  await db.from('payment_reversals').insert({ payment_id, reversed_by: user.id, reason: sanitizeString(reason) });

  // Kapag ang na-reverse na payment ay galing sa rider collection na hindi pa
  // naka-submit ng proof, i-REOPEN ang assignment (bumalik sa `accepted`).
  // Kung hindi ito gawin, mananatili itong `in_progress` na walang verified
  // payment — at ang `fn=upload-proof` ay laging tatanggi ng 409
  // PAYMENT_NOT_RECORDED, kaya hindi na matatapos ng rider ang koleksyon
  // (naka-stuck sa "In Progress — collected, awaiting proof").
  if (payment.collection_assignment_id) {
    try {
      await db
        .from('collection_assignments')
        .update({ status: 'accepted', amount_collected: null, completed_at: null })
        .eq('id', payment.collection_assignment_id)
        .eq('status', 'in_progress');
    } catch (e) {
      console.warn('[payments-reverse] collection reopen failed', e);
    }
  }
  const loanId = await getPaymentLoanId(db, payment);
  if (loanId) await db.from('loans').update({ status: 'active' }).eq('id', loanId);
  const lenderId = loanId
    ? (await db.from('loans').select('lender_id').eq('id', loanId).single()).data?.lender_id
    : null;
  await writeAuditLog({ performedBy: user.id, action: 'payment_reverse', tableName: 'payments', recordId: payment_id, oldValues: { status: 'verified', amount: payment.amount }, newValues: { status: 'reversed', reason }, ipAddress: ip });
  if (lenderId) {
    await sendPushNotification({ userId: lenderId, title: 'Payment Reversed', body: `A payment of ₱${Number(payment.amount).toLocaleString()} has been reversed.`, type: 'payment_reversed', referenceId: payment_id });
  }
  return jsonResponse({ message: 'Payment reversed, balance restored' });
}