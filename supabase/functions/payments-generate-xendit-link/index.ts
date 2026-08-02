// supabase/functions/payments-generate-xendit-link/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { createInvoice } from '../_shared/xendit.ts';
import { writeAuditLog } from '../_shared/audit.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;
    const roleCheck = requireRole(user, ROLES.LENDER);
    if (roleCheck) return roleCheck;
    const { loan_id, loan_schedule_id } = await req.json();
    if (!loan_id || !loan_schedule_id) return errorResponse('loan_id and loan_schedule_id required', 400, 'VALIDATION_ERROR');
    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
    const { data: loan } = await db.from('loans').select('id, loan_number, user_id, status').eq('id', loan_id).eq('user_id', user.id).single();
    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (loan.status !== 'active') return errorResponse('Loan is not active', 400, 'INVALID_STATUS');
    const { data: schedule } = await db.from('loan_schedules').select('id, amount_due, status, due_date').eq('id', loan_schedule_id).eq('loan_id', loan_id).single();
    if (!schedule) return errorResponse('Schedule not found', 404, 'NOT_FOUND');
    if (schedule.status === 'paid') return errorResponse('Installment already paid', 400, 'PAYMENT_ALREADY_MADE');
    const { data: userInfo } = await db.from('users').select('email, first_name, last_name').eq('id', user.id).single();
    const externalId = `${loan.loan_number}-SCHED-${loan_schedule_id}-${Date.now()}`;
    const invoice = await createInvoice({ externalId, amount: schedule.amount_due, payerEmail: userInfo?.email ?? undefined, description: `Payment for ${loan.loan_number} installment due ${schedule.due_date}` });
    const { data: payment } = await db.from('payments').insert({ loan_id, loan_schedule_id, amount: schedule.amount_due, method: 'gcash', status: 'pending', xendit_invoice_id: invoice.id, xendit_external_id: externalId }).select('id').single();
    await db.from('xendit_logs').insert({ reference_type: 'invoice', xendit_id: invoice.id, external_id: externalId, amount: schedule.amount_due, status: 'created', payload: invoice });
    await writeAuditLog({ performedBy: user.id, action: 'generate_gcash_link', tableName: 'payments', recordId: payment.id, ipAddress: ip });
    return jsonResponse({ invoice_url: invoice.invoiceUrl, xendit_invoice_id: invoice.id, payment_id: payment.id });
  } catch (err) {
    console.error('payments-generate-xendit-link error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});