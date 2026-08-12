// supabase/functions/disbursements-select/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// Lets the LENDER choose how they want to receive their loan proceeds AFTER
// their application has been approved (head manager / employee).
//
//   ?fn=select    body: { loan_id, method, gcash_number? }
//
//   method = 'gcash'        → records the preference AND, when a valid GCash
//                             number is provided, releases the loan immediately
//                             (auto-disbursement → status becomes 'active').
//   method = 'office_cash'  → records the preference only; a staff member
//                             releases the cash at the office later.
//   method = 'rider_delivery'→ records the preference only; a staff member
//                             schedules the rider delivery later.
//
// A loan awaiting the lender's method has status 'approved'. Once released the
// loan moves to 'active' (GCash auto-release) or stays 'approved' until a staff
// member fulfils the chosen office / rider method.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validateUUID } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { createDisbursement } from '../_shared/xendit.ts';

const ALLOWED_METHODS = ['gcash', 'office_cash', 'rider_delivery'];

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? 'select';
    if (fn !== 'select') {
      return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }

    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.LENDER);
    if (roleCheck) return roleCheck;

    const body = await req.json().catch(() => ({}));
    const { loan_id, method, gcash_number } = body;

    if (!loan_id || !validateUUID(loan_id)) {
      return errorResponse('Valid loan_id is required', 400, 'VALIDATION_ERROR');
    }
    const normalizedMethod = String(method ?? '').toLowerCase();
    if (!ALLOWED_METHODS.includes(normalizedMethod)) {
      return errorResponse('Invalid disbursement method', 400, 'VALIDATION_ERROR');
    }
    if (normalizedMethod === 'gcash' && !/^09\d{9}$/.test(String(gcash_number ?? '').trim())) {
      return errorResponse('Valid GCash number is required (09XXXXXXXXX)', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: loan } = await db
      .from('loans')
      .select('id, loan_number, lender_id, principal_amount, status')
      .eq('id', loan_id)
      .single();

    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (loan.lender_id !== authResult.id) {
      return errorResponse('Access denied', 403, 'FORBIDDEN');
    }
    if (loan.status !== 'approved') {
      return errorResponse('Loan must be in approved status to choose a disbursement method', 400, 'INVALID_STATUS');
    }

    const gcash = normalizedMethod === 'gcash' ? String(gcash_number).trim() : null;

    // Record the borrower's chosen preference (upsert, 1:1 with the loan).
    await db.from('loan_disbursement_preferences').upsert(
      { loan_id, method: normalizedMethod, account: gcash },
      { onConflict: 'loan_id' },
    );

    // GCash → auto-release immediately.
    if (normalizedMethod === 'gcash') {
      const { count: disbCount } = await db
        .from('disbursements')
        .select('*', { count: 'exact', head: true })
        .eq('loan_id', loan_id);
      if ((disbCount ?? 0) > 0) {
        return errorResponse('Loan has already been disbursed', 400, 'DUPLICATE');
      }

      const externalId = `DISB-${loan.loan_number}-${Date.now()}`;
      const amount = Number(loan.principal_amount);

      const xenditResult = await createDisbursement({
        externalId,
        bankCode: 'GCASH',
        accountHolderName: 'Lender',
        accountNumber: gcash!,
        amount,
        description: `Loan disbursement ${loan.loan_number}`,
      });

      const now = new Date().toISOString();
      const { data: disbursement, error: disbErr } = await db
        .from('disbursements')
        .insert({
          loan_id,
          method: 'gcash',
          amount,
          xendit_id: xenditResult.id,
          xendit_reference: externalId,
          xendit_status: xenditResult.status,
          authorized_by: authResult.id,
          disbursed_at: now,
          status: xenditResult.status === 'COMPLETED' ? 'completed' : 'pending',
        })
        .select()
        .single();

      if (disbErr) throw disbErr;

      if (xenditResult.status === 'COMPLETED') {
        await db.from('loans').update({ status: 'active' }).eq('id', loan_id);
      }

      await writeAuditLog({
        performedBy: authResult.id,
        action: 'disburse_gcash',
        tableName: 'disbursements',
        recordId: disbursement.id,
        newValues: { loan_id, gcash_number: gcash, amount, xendit_id: xenditResult.id },
        ipAddress: ip,
      });

      await sendPushNotification({
        userId: loan.lender_id,
        title: 'Loan Disbursed via GCash',
        body: `Your loan of ₱${amount.toLocaleString()} has been disbursed to ${gcash}.`,
        type: 'disbursement',
        referenceId: loan_id,
        sentBy: authResult.id,
      });

      await notifyStaffForSelection({ loanId: loan_id, method: 'gcash', db });

      return jsonResponse({
        success: true,
        status: 'released',
        method: 'gcash',
        disbursement,
      });
    }

    // office_cash / rider_delivery → recorded; staff fulfils later.
    await writeAuditLog({
      performedBy: authResult.id,
      action: 'disbursement_selected',
      tableName: 'loan_disbursement_preferences',
      recordId: loan_id,
      newValues: { loan_id, method: normalizedMethod },
      ipAddress: ip,
    });

    await sendPushNotification({
      userId: loan.lender_id,
      title: normalizedMethod === 'office_cash' ? 'Office Cash Selection Received' : 'Rider Delivery Selection Received',
      body: normalizedMethod === 'office_cash'
        ? `We'll notify you when your loan of ₱${Number(loan.principal_amount).toLocaleString()} is ready for pickup at the office.`
        : `A rider will be scheduled to deliver your loan of ₱${Number(loan.principal_amount).toLocaleString()} to your registered address.`,
      type: 'disbursement',
      referenceId: loan_id,
      sentBy: authResult.id,
    });

    await notifyStaffForSelection({ loanId: loan_id, method: normalizedMethod, db });

    return jsonResponse({
      success: true,
      status: 'awaiting_staff',
      method: normalizedMethod,
    });
  } catch (err) {
    console.error('disbursements-select error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// Notify head_manager / employee that an approved loan now has a disbursement
// method selected and is ready to be fulfilled.
async function notifyStaffForSelection(params: {
  loanId: string;
  method: string;
  db: ReturnType<typeof getAdminClient>;
}): Promise<void> {
  try {
    const { data: users } = await params.db
      .from('users')
      .select('id, roles!inner(name)')
      .or('roles.name.eq.head_manager,roles.name.eq.employee')
      .eq('account_status', 'active');

    const methodLabel =
      params.method === 'gcash' ? 'GCash' :
      params.method === 'office_cash' ? 'Office Cash' : 'Rider Delivery';

    await Promise.all(
      (users ?? []).map((u) =>
        sendPushNotification({
          userId: u.id,
          title: 'Disbursement Method Selected',
          body: `A lender chose ${methodLabel} for loan disbursement and it is ready to be fulfilled.`,
          type: 'disbursement',
          referenceId: params.loanId,
        })
      )
    );
  } catch (err) {
    console.error('notify staff of selection failed:', err);
  }
}
