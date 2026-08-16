// supabase/functions/disbursements-delivery/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   disbursements-office-cash    →  ?fn=office-cash
//   disbursements-rider-delivery →  ?fn=rider-delivery
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
import { sendPushNotification } from '../_shared/notifications.ts';
import { validateUUID } from '../_shared/validators.ts';

const PROOF_BUCKET = 'disbursement-proofs';

const DISB_PROOF_COLUMN_BY_TYPE: Record<string, string> = {
  proof_photo: 'delivery_proof',
  signature: 'borrower_signature',
};

function decodeBase64(content: string): Uint8Array {
  const binary = atob(content);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

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
const DEFAULT_ACTION = 'office-cash';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'office-cash':
        // ── [moved from functions/disbursements-office-cash/index.ts] ───
        return await handleOfficeCash(req);
      case 'rider-delivery':
        // ── [moved from functions/disbursements-rider-delivery/index.ts] ─
        return await handleRiderDelivery(req);
      case 'upload-proof':
        // ── rider uploads proof of cash delivery ─────────────────────────
        return await handleUploadProof(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('disbursements-delivery error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/disbursements-office-cash/index.ts] ────────────────
async function handleOfficeCash(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const body = await req.json().catch(() => ({}));
  const { loan_id, notes } = body;

  if (!loan_id || !validateUUID(loan_id)) {
    return errorResponse('Valid loan_id is required', 400, 'VALIDATION_ERROR');
  }

  const db = getAdminClient();

  const { data: loan, error: loanErr } = await db
    .from('loans')
    .select('id, loan_number, lender_id, principal_amount, status')
    .eq('id', loan_id)
    .single();

  if (loanErr || !loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
  if (loan.status !== 'approved') {
    return errorResponse('Loan must be in approved status to disburse', 400, 'INVALID_STATUS');
  }

  const { count: disbCount } = await db.from('disbursements').select('*', { count: 'exact', head: true }).eq('loan_id', loan_id);
  if ((disbCount ?? 0) > 0) {
    return errorResponse('Loan has already been disbursed', 400, 'DUPLICATE');
  }

  const { data: accountUpgradeDocs } = await db
    .from('account_upgrade_documents')
    .select('status')
    .eq('lender_id', loan.lender_id);

  if (!accountUpgradeDocs || accountUpgradeDocs.length === 0) {
    return errorResponse('Account Upgrade documents not found. Identity verification required before office cash release.', 400, 'ACCOUNT_UPGRADE_NOT_VERIFIED');
  }
  const allVerified = accountUpgradeDocs.every((d) => d.status === 'verified');
  if (!allVerified) {
    return errorResponse('All Account Upgrade documents must be verified before releasing office cash.', 400, 'ACCOUNT_UPGRADE_NOT_VERIFIED');
  }

  const now = new Date().toISOString();
  const amount = Number(loan.principal_amount);

  const { data: disbursement, error: disbErr } = await db
    .from('disbursements')
    .insert({
      loan_id,
      method: 'office_cash',
      amount,
      delivery_notes: notes ?? null,
      authorized_by: authResult.id,
      disbursed_at: now,
      status: 'completed',
    })
    .select()
    .single();

  if (disbErr) throw disbErr;

  await db
    .from('loans')
    .update({ status: 'active' })
    .eq('id', loan_id);

  await writeAuditLog({
    performedBy: authResult.id,
    action: 'disburse_office_cash',
    tableName: 'disbursements',
    recordId: disbursement.id,
    newValues: { loan_id, amount, notes },
  });

  await sendPushNotification({
    userId: loan.lender_id,
    title: 'Loan Released — Office Cash',
    body: `Your loan of ₱${amount.toLocaleString()} has been released. Please collect at our office.`,
    type: 'disbursement',
    referenceId: loan_id,
    sentBy: authResult.id,
  });

  return jsonResponse({ success: true, disbursement });
}

// ── [moved from functions/disbursements-rider-delivery/index.ts] ─────────────
async function handleRiderDelivery(req: Request) {
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
    .select('id, loan_number, lender_id, principal_amount, status')
    .eq('id', loan_id)
    .single();

  if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
  if (loan.status !== 'approved') return errorResponse('Loan must be approved to disburse', 400, 'INVALID_STATUS');

  const { count: disbCount } = await db.from('disbursements').select('*', { count: 'exact', head: true }).eq('loan_id', loan_id);
  if ((disbCount ?? 0) > 0) return errorResponse('Loan already disbursed', 400, 'DUPLICATE');

  const { data: rider } = await db
    .from('rider_profiles')
    .select('id, is_available')
    .eq('id', rider_id)
    .single();

  if (!rider) return errorResponse('Rider not found', 404, 'NOT_FOUND');
  if (!rider.is_available) return errorResponse('Rider is not available', 400, 'INVALID_STATUS');

  const amount = Number(loan.principal_amount);

  // The cash has NOT been handed over yet — only a rider was assigned. Keep
  // disbursed_at null so the lender's app keeps showing the "approved /
  // awaiting release" card instead of treating the loan as already disbursed.
  const { data: disbursement, error: disbErr } = await db
    .from('disbursements')
    .insert({
      loan_id,
      method: 'rider_delivery',
      amount,
      rider_id,
      delivery_date,
      delivery_notes: notes ?? null,
      authorized_by: authResult.id,
      disbursed_at: null,
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
}

// ── rider uploads proof that the cash was handed to the lender ──────────────
async function handleUploadProof(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const roleCheck = requireRole(user, ROLES.RIDER);
  if (roleCheck) return roleCheck;

  const { disbursement_id, proofs } = await req.json().catch(() => ({}));
  if (!disbursement_id || !validateUUID(disbursement_id)) {
    return errorResponse('Valid disbursement_id is required', 400, 'VALIDATION_ERROR');
  }
  if (!Array.isArray(proofs) || proofs.length === 0) {
    return errorResponse('proofs[] is required', 400, 'VALIDATION_ERROR');
  }
  if (!proofs.some((p) => p?.type === 'proof_photo')) {
    return errorResponse('At least one proof_photo is required', 400, 'VALIDATION_ERROR');
  }

  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

  const { data: disbursement } = await db
    .from('disbursements')
    .select('id, status, rider_id, loan_id, method, amount, delivery_proof')
    .eq('id', disbursement_id)
    .eq('rider_id', user.id)
    .single();

  if (!disbursement) return errorResponse('Disbursement not found', 404, 'NOT_FOUND');
  if (disbursement.method !== 'rider_delivery') {
    return errorResponse('Only rider delivery disbursements accept delivery proof', 400, 'INVALID_METHOD');
  }
  if (disbursement.status !== 'pending') {
    return errorResponse('Disbursement is not in pending status', 400, 'INVALID_STATUS');
  }

  const { data: loan } = await db
    .from('loans')
    .select('id, loan_number, lender_id, status')
    .eq('id', disbursement.loan_id)
    .single();

  if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
  if (loan.status !== 'approved') {
    return errorResponse('Loan must be approved to be released', 400, 'INVALID_STATUS');
  }

  const updates: Record<string, string> = {};
  for (const proof of proofs) {
    const type = proof?.type as string;
    const column = DISB_PROOF_COLUMN_BY_TYPE[type];
    if (!column || !proof.content_base64) continue;

    const ext = extFromMime(proof.mime_type);
    const path = `${disbursement_id}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
    const bytes = decodeBase64(proof.content_base64);

    const { error: uploadError } = await db.storage
      .from(PROOF_BUCKET)
      .upload(path, bytes, { contentType: proof.mime_type ?? 'image/jpeg', upsert: true });

    if (uploadError) {
      console.warn('disbursement proof storage upload failed, falling back to data uri:', uploadError.message);
      const mime = proof.mime_type ?? 'image/jpeg';
      updates[column] = `data:${mime};base64,${proof.content_base64}`;
    } else {
      const { data: signedUrl } = await db.storage.from(PROOF_BUCKET).createSignedUrl(path, 3600 * 24 * 7);
      updates[column] = signedUrl?.signedUrl ?? path;
    }
  }

  if (Object.keys(updates).length === 0) {
    return errorResponse('No valid proofs provided', 400, 'VALIDATION_ERROR');
  }

  const { error: disbUpdateErr } = await db
    .from('disbursements')
    .update({
      ...updates,
      status: 'completed',
      disbursed_at: new Date().toISOString(),
      delivered_at: new Date().toISOString(),
    })
    .eq('id', disbursement_id);

  if (disbUpdateErr) {
    console.error('disbursement proof update failed:', disbUpdateErr);
    return errorResponse('Failed to update disbursement: ' + disbUpdateErr.message, 500, 'SERVER_ERROR');
  }

  await db.from('loans').update({ status: 'active' }).eq('id', disbursement.loan_id);

  await writeAuditLog({
    performedBy: user.id,
    action: 'disbursement_delivery_proof',
    tableName: 'disbursements',
    recordId: disbursement_id,
    newValues: { status: 'completed', loan_status: 'active' },
    ipAddress: ip,
  });

  await sendPushNotification({
    userId: loan.lender_id,
    title: 'Loan Delivered — Cash via Rider',
    body: `Your loan of ₱${Number(disbursement.amount).toLocaleString()} has been delivered to you.`,
    type: 'disbursement',
    referenceId: disbursement.loan_id,
    sentBy: user.id,
  });

  return jsonResponse({ success: true, message: 'Delivery proof uploaded and loan released' });
}