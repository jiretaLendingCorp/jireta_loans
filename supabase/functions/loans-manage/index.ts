// supabase/functions/loans-manage/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   loans-approve        →  ?fn=approve
//   loans-reject         →  ?fn=reject
//   loans-cancel         →  ?fn=cancel
//   loans-apply-penalty  →  ?fn=apply-penalty
//   loans-request-ci     →  ?fn=request-ci
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
import { getLoanFinancials, hasPenaltyApplied } from '../_shared/loan_financials.ts';
import { embedAsObject } from '../_shared/types.ts';

// ── [moved from loans-apply-penalty] ────────────────────────────────────────
const PENALTY_RATE = 0.20;

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'approve';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'approve':
        // ── [moved from functions/loans-approve/index.ts] ────────────────
        return await handleApprove(req);
      case 'reject':
        // ── [moved from functions/loans-reject/index.ts] ─────────────────
        return await handleReject(req);
      case 'cancel':
        // ── [moved from functions/loans-cancel/index.ts] ─────────────────
        return await handleCancel(req);
      case 'apply-penalty':
        // ── [moved from functions/loans-apply-penalty/index.ts] ──────────
        return await handleApplyPenalty(req);
      case 'request-ci':
        // ── [moved from functions/loans-request-ci/index.ts] ─────────────
        return await handleRequestCi(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('loans-manage error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/loans-approve/index.ts] ───────────────────────────
async function handleApprove(req: Request) {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const { loan_id } = await req.json();
    if (!loan_id) return errorResponse('loan_id is required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: loan } = await db.from('loans')
      .select('id, status, lender_id, lender_profiles(kyc_status)')
      .eq('id', loan_id).single();

    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (!['pending', 'under_review', 'ci_required', 'ci_assigned', 'ci_completed'].includes(loan.status)) {
      return errorResponse(`Loan cannot be approved from ${loan.status} status`, 400, 'INVALID_STATUS');
    }

    const lp = embedAsObject(loan?.lender_profiles);
    if (lp?.kyc_status !== 'verified') return errorResponse('Lender KYC must be verified', 400, 'KYC_NOT_VERIFIED');

    await db.from('loans').update({ status: 'approved', approved_by: user.id }).eq('id', loan_id);

    await writeAuditLog({ performedBy: user.id, action: 'loan_approve', tableName: 'loans', recordId: loan_id, oldValues: { status: loan.status }, newValues: { status: 'approved' }, ipAddress: ip });
    await sendPushNotification({ userId: loan.lender_id, title: 'Loan Approved', body: 'Congratulations! Your loan has been approved. Please choose how you want to receive the funds to complete the release.', type: 'loan_approved', referenceId: loan_id });

    return jsonResponse({ message: 'Loan approved successfully' });
}

// ── [moved from functions/loans-reject/index.ts] ────────────────────────────
async function handleReject(req: Request) {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const { loan_id, rejection_reason } = await req.json();
    if (!loan_id || !rejection_reason) return errorResponse('loan_id and rejection_reason are required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: loan } = await db.from('loans').select('id, status, lender_id').eq('id', loan_id).single();
    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (['active', 'completed', 'rejected', 'cancelled'].includes(loan.status)) {
      return errorResponse(`Cannot reject loan in ${loan.status} status`, 400, 'INVALID_STATUS');
    }

    await db.from('loans').update({ status: 'rejected', rejected_by: user.id, rejection_reason: sanitizeString(rejection_reason) }).eq('id', loan_id);

    await writeAuditLog({ performedBy: user.id, action: 'loan_reject', tableName: 'loans', recordId: loan_id, oldValues: { status: loan.status }, newValues: { status: 'rejected', rejection_reason }, ipAddress: ip });
    await sendPushNotification({ userId: loan.lender_id, title: 'Loan Application Rejected', body: `Your loan was rejected: ${sanitizeString(rejection_reason)}`, type: 'loan_rejected', referenceId: loan_id });

    return jsonResponse({ message: 'Loan rejected' });
}

// ── [moved from functions/loans-cancel/index.ts] ────────────────────────────
async function handleCancel(req: Request) {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const { loan_id } = await req.json();
    if (!loan_id) return errorResponse('loan_id is required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: loan } = await db.from('loans').select('id, status, lender_id').eq('id', loan_id).single();
    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');

    if (user.role === ROLES.LENDER && loan.lender_id !== user.id) {
      return errorResponse('Access denied', 403, 'FORBIDDEN');
    }

    if (!['pending', 'under_review'].includes(loan.status)) {
      return errorResponse(`Cannot cancel loan in ${loan.status} status`, 400, 'INVALID_STATUS');
    }

    await db.from('loans').update({ status: 'cancelled' }).eq('id', loan_id);
    await writeAuditLog({ performedBy: user.id, action: 'loan_cancel', tableName: 'loans', recordId: loan_id, oldValues: { status: loan.status }, newValues: { status: 'cancelled' }, ipAddress: ip });

    return jsonResponse({ message: 'Loan cancelled' });
}

// ── [moved from functions/loans-apply-penalty/index.ts] ─────────────────────
async function handleApplyPenalty(req: Request) {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const { loan_id, reason } = await req.json();
    if (!loan_id) return errorResponse('loan_id is required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: loan } = await db.from('loans').select('id, status, lender_id').eq('id', loan_id).single();
    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (loan.status !== 'overdue') return errorResponse('Penalty can only be applied to overdue loans', 400, 'INVALID_STATUS');

    if (await hasPenaltyApplied(db, loan_id)) return errorResponse('Penalty already applied', 400, 'DUPLICATE');

    const financials = await getLoanFinancials(db, loan_id);
    const penaltyAmount = Math.round((financials?.total_payable ?? 0) * PENALTY_RATE * 100) / 100;
    const newBalance = Math.round(((financials?.outstanding_balance ?? 0) + penaltyAmount) * 100) / 100;

    await db.from('penalty_logs').insert({ loan_id, applied_by: user.id, penalty_rate: PENALTY_RATE, penalty_basis: financials?.total_payable ?? 0, penalty_amount: penaltyAmount, reason: reason ?? 'Overdue penalty applied' });

    await writeAuditLog({ performedBy: user.id, action: 'apply_penalty', tableName: 'penalty_logs', recordId: loan_id, oldValues: { outstanding_balance: financials?.outstanding_balance }, newValues: { outstanding_balance: newBalance, penalty_amount: penaltyAmount }, ipAddress: ip });
    await sendPushNotification({ userId: loan.lender_id, title: 'Overdue Penalty Applied', body: `A 20% penalty of ₱${penaltyAmount.toLocaleString()} has been added to your outstanding balance.`, type: 'penalty_applied', referenceId: loan_id });

    return jsonResponse({ message: 'Penalty applied', penalty_amount: penaltyAmount, new_balance: newBalance });
}

// ── [moved from functions/loans-request-ci/index.ts] ────────────────────────
async function handleRequestCi(req: Request) {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const { loan_id } = await req.json();
    if (!loan_id) return errorResponse('loan_id is required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: loan } = await db.from('loans').select('id, status, lender_id').eq('id', loan_id).single();
    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (!['pending', 'under_review'].includes(loan.status)) return errorResponse('Loan must be pending or under_review to request CI', 400, 'INVALID_STATUS');

    // CI is REQUESTED here, not assigned. The `ci_assigned` status is reserved
    // for a loan with an actual credit_investigations row + an available rider
    // (ci-assign). Flagging as `ci_required` keeps the list honest: without an
    // assignment the loan shows "CI Required", never "CI Assigned".
    await db.from('loans').update({ status: 'ci_required' }).eq('id', loan_id);
    await writeAuditLog({ performedBy: user.id, action: 'request_ci', tableName: 'loans', recordId: loan_id, oldValues: { status: loan.status }, newValues: { status: 'ci_required' }, ipAddress: ip });
    await sendPushNotification({ userId: loan.lender_id, title: 'Credit Investigation Required', body: 'Your loan requires a credit investigation. A rider will visit your address.', type: 'ci_required', referenceId: loan_id });

    return jsonResponse({ message: 'CI requested' });
}