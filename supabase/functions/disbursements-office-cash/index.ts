// supabase/functions/disbursements-office-cash/index.ts
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
    const { loan_id, notes } = body;

    if (!loan_id || !validateUUID(loan_id)) {
      return errorResponse('Valid loan_id is required', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();

    const { data: loan, error: loanErr } = await db
      .from('loans')
      .select('id, loan_number, lender_id, principal_amount, status, disbursement_method')
      .eq('id', loan_id)
      .single();

    if (loanErr || !loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (loan.status !== 'approved') {
      return errorResponse('Loan must be in approved status to disburse', 400, 'INVALID_STATUS');
    }
    if (loan.disbursement_method) {
      return errorResponse('Loan has already been disbursed', 400, 'DUPLICATE');
    }

    const { data: kycDocs } = await db
      .from('kyc_documents')
      .select('status')
      .eq('lender_id', loan.lender_id);

    if (!kycDocs || kycDocs.length === 0) {
      return errorResponse('KYC documents not found. Identity verification required before office cash release.', 400, 'KYC_NOT_VERIFIED');
    }
    const allVerified = kycDocs.every((d: any) => d.status === 'verified');
    if (!allVerified) {
      return errorResponse('All KYC documents must be verified before releasing office cash.', 400, 'KYC_NOT_VERIFIED');
    }

    const now = new Date().toISOString();
    const amount = Number(loan.principal_amount);

    const { data: disbursement, error: disbErr } = await db
      .from('disbursements')
      .insert({
        loan_id,
        lender_id: loan.lender_id,
        disbursement_method: 'office_cash',
        amount,
        notes: notes ?? null,
        disbursed_by: authResult.id,
        disbursed_at: now,
        status: 'completed',
      })
      .select()
      .single();

    if (disbErr) throw disbErr;

    await db
      .from('loans')
      .update({ status: 'active', disbursement_method: 'office_cash', disbursed_at: now })
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
  } catch (err) {
    console.error('disbursements-office-cash error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});