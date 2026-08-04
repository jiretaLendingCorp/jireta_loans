// supabase/functions/kpi-lender/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.LENDER);
    if (roleCheck) return roleCheck;

    const db = getAdminClient();
    const lenderId = authResult.id;

    const [
      { count: totalApplications },
      { count: totalApproved },
      { count: totalRejected },
      { count: totalActive },
      { count: totalCompleted },
    ] = await Promise.all([
      db.from('loans').select('*', { count: 'exact', head: true }).eq('lender_id', lenderId),
      db.from('loans').select('*', { count: 'exact', head: true })
        .eq('lender_id', lenderId).in('status', ['approved', 'active', 'completed']),
      db.from('loans').select('*', { count: 'exact', head: true })
        .eq('lender_id', lenderId).eq('status', 'rejected'),
      db.from('loans').select('*', { count: 'exact', head: true })
        .eq('lender_id', lenderId).eq('status', 'active'),
      db.from('loans').select('*', { count: 'exact', head: true })
        .eq('lender_id', lenderId).eq('status', 'completed'),
    ]);

    const { data: loanData } = await db
      .from('loans')
      .select('principal_amount, outstanding_balance, penalty_applied')
      .eq('lender_id', lenderId)
      .in('status', ['active', 'completed', 'overdue']);

    const { data: paymentData } = await db
      .from('payments')
      .select('amount, loans!payments_loan_id_fkey(lender_id)')
      .eq('loans.lender_id', lenderId)
      .eq('status', 'verified');

    const { data: penaltyData } = await db
      .from('penalty_logs')
      .select('penalty_amount, loans!penalty_logs_loan_id_fkey(lender_id)')
      .eq('loans.lender_id', lenderId);

    let totalBorrowed = 0, totalOutstanding = 0, totalInterestPaid = 0;
    (loanData ?? []).forEach((l: any) => {
      totalBorrowed += Number(l.principal_amount);
      totalOutstanding += Number(l.outstanding_balance);
    });

    let totalPaid = 0;
    (paymentData ?? []).forEach((p: any) => { totalPaid += Number(p.amount); });

    let totalPenaltiesPaid = 0;
    (penaltyData ?? []).forEach((p: any) => { totalPenaltiesPaid += Number(p.penalty_amount); });

    totalInterestPaid = totalPaid - (totalBorrowed - totalOutstanding);

    return jsonResponse({
      total_applications: totalApplications ?? 0,
      total_approved: totalApproved ?? 0,
      total_rejected: totalRejected ?? 0,
      total_active: totalActive ?? 0,
      total_completed: totalCompleted ?? 0,
      total_borrowed: totalBorrowed,
      total_paid: totalPaid,
      remaining_balance: totalOutstanding,
      total_interest_paid: Math.max(0, totalInterestPaid),
      total_penalties_paid: totalPenaltiesPaid,
    });
  } catch (err) {
    console.error('kpi-lender error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});