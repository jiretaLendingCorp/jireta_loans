// supabase/functions/kpi-head-manager/index.ts
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
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const db = getAdminClient();

    const [
      { count: totalEmployees },
      { count: totalRiders },
      { count: totalLenders },
      { count: totalApplications },
      { count: totalApproved },
      { count: totalRejected },
      { count: totalActive },
      { count: totalCompleted },
      { count: totalOverdue },
      { count: totalCi },
      { count: totalReports },
      { count: totalPendingKyc },
      { count: totalCollectionTx },
    ] = await Promise.all([
      db.from('users').select('*, roles!inner(name)', { count: 'exact', head: true }).eq('roles.name', 'employee').neq('account_status', 'archived'),
      db.from('users').select('*, roles!inner(name)', { count: 'exact', head: true }).eq('roles.name', 'rider').neq('account_status', 'archived'),
      db.from('users').select('*, roles!inner(name)', { count: 'exact', head: true }).eq('roles.name', 'lender').neq('account_status', 'archived'),
      db.from('loans').select('*', { count: 'exact', head: true }),
      db.from('loans').select('*', { count: 'exact', head: true }).in('status', ['approved', 'active', 'completed']),
      db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'rejected'),
      db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'active'),
      db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'completed'),
      db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'overdue'),
      db.from('credit_investigations').select('*', { count: 'exact', head: true }),
      db.from('reports').select('*', { count: 'exact', head: true }),
      db.from('lender_profiles').select('*', { count: 'exact', head: true }).eq('kyc_status', 'submitted'),
      db.from('payments').select('*', { count: 'exact', head: true }).eq('status', 'verified'),
    ]);

    const { data: financials } = await db
      .from('loans')
      .select('principal_amount, total_payable, outstanding_balance')
      .in('status', ['active', 'completed', 'overdue']);

    const { data: payments } = await db
      .from('payments')
      .select('amount, payment_method')
      .eq('status', 'verified');

    const { data: penalties } = await db
      .from('penalty_logs')
      .select('penalty_amount');

    let totalReleased = 0, totalOutstanding = 0, totalInterest = 0;
    (financials ?? []).forEach((l: any) => {
      totalReleased += Number(l.principal_amount);
      totalOutstanding += Number(l.outstanding_balance);
      totalInterest += Math.max(0, Number(l.total_payable) - Number(l.principal_amount));
    });

    let totalCollected = 0;
    (payments ?? []).forEach((p: any) => { totalCollected += Number(p.amount); });

    let totalPenalties = 0;
    (penalties ?? []).forEach((p: any) => { totalPenalties += Number(p.penalty_amount); });

    return jsonResponse({
      total_employees: totalEmployees ?? 0,
      total_riders: totalRiders ?? 0,
      total_lenders: totalLenders ?? 0,
      total_loan_applications: totalApplications ?? 0,
      total_approved_loans: totalApproved ?? 0,
      total_rejected_loans: totalRejected ?? 0,
      total_active_loans: totalActive ?? 0,
      total_completed_loans: totalCompleted ?? 0,
      total_overdue_loans: totalOverdue ?? 0,
      total_loan_amount_released: totalReleased,
      total_amount_collected: totalCollected,
      total_outstanding_balance: totalOutstanding,
      total_interest_earned: totalInterest,
      total_penalties_collected: totalPenalties,
      total_revenue: totalInterest + totalPenalties,
      total_collection_transactions: totalCollectionTx ?? 0,
      total_ci_assignments: totalCi ?? 0,
      total_report_exports: totalReports ?? 0,
      total_pending_kyc: totalPendingKyc ?? 0,
    });
  } catch (err) {
    console.error('kpi-head-manager error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});