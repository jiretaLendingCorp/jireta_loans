
// supabase/functions/loans-get-details/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const url = new URL(req.url);
    const loanId = url.searchParams.get('loan_id');
    if (!loanId) return errorResponse('loan_id is required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();

    const { data: loan } = await db.from('loans')
      .select(`*, lender_profiles!loans_lender_id_fkey(id, kyc_status, is_blacklisted, gcash_number, employment_type, employer_name, monthly_income, users:users!lender_profiles_id_fkey(id, first_name, middle_name, last_name, phone_number, email))`)
      .eq('id', loanId).single();

    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (user.role === ROLES.LENDER && loan.lender_id !== user.id) return errorResponse('Access denied', 403, 'FORBIDDEN');
    if (user.role === ROLES.RIDER) return errorResponse('Access denied', 403, 'FORBIDDEN');

    const { data: schedule } = await db.from('loan_schedules').select('*').eq('loan_id', loanId).order('installment_number');
    const { data: payments } = await db.from('payments').select('*').eq('loan_id', loanId).order('created_at', { ascending: false });
    const { data: ci } = await db.from('credit_investigations').select('*').eq('loan_id', loanId).order('created_at', { ascending: false });
    const { data: disbursements } = await db.from('disbursements').select('*').eq('loan_id', loanId).order('created_at', { ascending: false });
    const { data: penalties } = await db.from('penalty_logs').select('*').eq('loan_id', loanId).order('applied_at', { ascending: false });

    const lp = (loan as any).lender_profiles;
    const loanOut: Record<string, unknown> = {
      ...loan,
      frequency: loan.payment_frequency,
      interest_amount: Math.max(0, Math.round((Number(loan.total_payable) - Number(loan.principal_amount)) * 100) / 100),
      lender: lp?.users ?? null,
      lender_profile: lp ?? null,
      loan_schedules: schedule ?? [],
      payments: payments ?? [],
      credit_investigations: ci ?? [],
      disbursements: disbursements ?? [],
      penalties: penalties ?? [],
    };

    return jsonResponse(loanOut);
  } catch (err) {
    console.error('loans-get-details error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
