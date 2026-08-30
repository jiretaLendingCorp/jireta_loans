// supabase/functions/kpi-view/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   kpi-head-manager →  ?fn=head-manager
//   kpi-employee     →  ?fn=employee
//   kpi-rider        →  ?fn=rider
//   kpi-lender       →  ?fn=lender
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { getLoanFinancialsBatch } from '../_shared/loan_financials.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'head-manager';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'head-manager':
        // ── [moved from functions/kpi-head-manager/index.ts] ───────────
        return await handleHeadManager(req);
      case 'employee':
        // ── [moved from functions/kpi-employee/index.ts] ───────────────
        return await handleEmployee(req);
      case 'rider':
        // ── [moved from functions/kpi-rider/index.ts] ──────────────────
        return await handleRider(req);
      case 'lender':
        // ── [moved from functions/kpi-lender/index.ts] ─────────────────
        return await handleLender(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('kpi-view error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/kpi-head-manager/index.ts] ────────────────────────
async function handleHeadManager(req: Request) {
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
    { count: totalPendingAccountUpgrade },
    { count: totalCollectionTx },
  ] = await Promise.all([
    db.from('users').select('*, roles!users_role_id_fkey!inner(name)', { count: 'exact', head: true }).eq('roles.name', 'employee').neq('account_status', 'archived'),
    db.from('users').select('*, roles!users_role_id_fkey!inner(name)', { count: 'exact', head: true }).eq('roles.name', 'rider').neq('account_status', 'archived'),
    db.from('users').select('*, roles!users_role_id_fkey!inner(name)', { count: 'exact', head: true }).eq('roles.name', 'lender').neq('account_status', 'archived'),
    db.from('loans').select('*', { count: 'exact', head: true }),
    db.from('loans').select('*', { count: 'exact', head: true }).in('status', ['approved', 'active', 'completed']),
    db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'rejected'),
    db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'active'),
    db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'completed'),
    db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'overdue'),
    db.from('credit_investigations').select('*', { count: 'exact', head: true }),
    db.from('reports').select('*', { count: 'exact', head: true }),
    db.from('lender_profiles').select('*', { count: 'exact', head: true }).eq('account_upgrade_status', 'submitted'),
    db.from('payments').select('*', { count: 'exact', head: true }).eq('status', 'verified'),
  ]);

  const { data: loanRows } = await db
    .from('loans')
    .select('id, principal_amount')
    .in('status', ['active', 'completed', 'overdue']);

  const financials = await getLoanFinancialsBatch(
    db,
    (loanRows ?? []).map((l) => l.id),
  );

  const { data: payments } = await db
    .from('payments')
    .select('amount, payment_method')
    .eq('status', 'verified');

  const { data: penalties } = await db
    .from('penalty_logs')
    .select('penalty_amount');

  let totalReleased = 0, totalOutstanding = 0, totalInterest = 0;
  (loanRows ?? []).forEach((l) => {
    const fin = financials[l.id] ?? null;
    totalReleased += Number(l.principal_amount);
    totalOutstanding += Number(fin?.outstanding_balance ?? 0);
    totalInterest += Number(fin?.interest_amount ?? 0);
  });

  let totalCollected = 0;
  (payments ?? []).forEach((p) => { totalCollected += Number(p.amount); });

  let totalPenalties = 0;
  (penalties ?? []).forEach((p) => { totalPenalties += Number(p.penalty_amount); });

  // ── Monthly trend series (last 6 months, oldest → newest) ──────────────
  const { data: trendLoans } = await db
    .from('loans')
    .select('created_at, status, principal_amount');
  const { data: trendDisbursements } = await db
    .from('disbursements')
    .select('disbursed_at, amount')
    .eq('status', 'completed');
  const { data: trendPayments } = await db
    .from('payments')
    .select('paid_at, amount')
    .eq('status', 'verified');

  const monthlySeries: Array<{
    month: string;
    applications: number;
    released: number;
    collected: number;
  }> = [];
  const now = new Date();
  for (let i = 5; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    const next = new Date(d.getFullYear(), d.getMonth() + 1, 1);
    const inRange = (ts: string | null | undefined) => {
      if (!ts) return false;
      const t = new Date(ts).getTime();
      return t >= d.getTime() && t < next.getTime();
    };
    monthlySeries.push({
      month: key,
      applications: (trendLoans ?? []).filter((l) => inRange(l.created_at)).length,
      released: (trendDisbursements ?? [])
        .filter((x) => inRange(x.disbursed_at))
        .reduce((s, x) => s + Number(x.amount), 0),
      collected: (trendPayments ?? [])
        .filter((p) => inRange(p.paid_at))
        .reduce((s, p) => s + Number(p.amount), 0),
    });
  }

  // ── Loan portfolio breakdown by status (for interactive donut drill-down) ─
  // Compute exact counts per status in a single pass; keeps donut tooltip
  // accurate even when new statuses are added and avoids N separate head queries.
  const loanStatusBreakdown: Record<string, number> = {};
  (trendLoans ?? []).forEach((r: { status: string }) => {
    const s = (r.status ?? 'unknown') as string;
    loanStatusBreakdown[s] = (loanStatusBreakdown[s] ?? 0) + 1;
  });
  // Ensure all known statuses appear (frontend expects stable keys for legend)
  const knownStatuses = [
    'pending',
    'under_review',
    'ci_required',
    'ci_assigned',
    'ci_completed',
    'approved',
    'active',
    'completed',
    'rejected',
    'cancelled',
    'overdue',
  ];
  for (const s of knownStatuses) {
    if (!(s in loanStatusBreakdown)) loanStatusBreakdown[s] = 0;
  }
  // Aggregate pending-like bucket that the old frontend derived ad-hoc.
  const pendingBucket = (loanStatusBreakdown['pending'] ?? 0) +
    (loanStatusBreakdown['under_review'] ?? 0) +
    (loanStatusBreakdown['ci_required'] ?? 0) +
    (loanStatusBreakdown['ci_assigned'] ?? 0) +
    (loanStatusBreakdown['ci_completed'] ?? 0) +
    (loanStatusBreakdown['approved'] ?? 0) +
    (loanStatusBreakdown['cancelled'] ?? 0);

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
    total_pending_account_upgrade: totalPendingAccountUpgrade ?? 0,
    monthly_series: monthlySeries,
    loan_status_breakdown: loanStatusBreakdown,
    pending_bucket: pendingBucket,
  });
}

// ── [moved from functions/kpi-employee/index.ts] ────────────────────────────
async function handleEmployee(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const db = getAdminClient();
  const empId = authResult.id;

  const [
    { count: totalLenders },
    { count: totalApplications },
    { count: totalApproved },
    { count: totalRejected },
    { count: totalActive },
    { count: totalCompleted },
    { count: totalCollections },
  ] = await Promise.all([
    db.from('users').select('*', { count: 'exact', head: true })
      .eq('created_by', empId).eq('roles.name', 'lender'),
    db.from('loans').select('*, in_office_applications!fk_loans_in_office(created_by)', { count: 'exact', head: true })
      .eq('in_office_applications.created_by', empId),
    db.from('loans').select('*, in_office_applications!fk_loans_in_office(created_by)', { count: 'exact', head: true })
      .eq('in_office_applications.created_by', empId).in('status', ['approved', 'active', 'completed']),
    db.from('loans').select('*, in_office_applications!fk_loans_in_office(created_by)', { count: 'exact', head: true })
      .eq('in_office_applications.created_by', empId).eq('status', 'rejected'),
    db.from('loans').select('*, in_office_applications!fk_loans_in_office(created_by)', { count: 'exact', head: true })
      .eq('in_office_applications.created_by', empId).eq('status', 'active'),
    db.from('loans').select('*, in_office_applications!fk_loans_in_office(created_by)', { count: 'exact', head: true })
      .eq('in_office_applications.created_by', empId).eq('status', 'completed'),
    db.from('collection_assignments').select('*', { count: 'exact', head: true })
      .eq('assigned_by', empId),
  ]);

  return jsonResponse({
    total_lenders_managed: totalLenders ?? 0,
    total_applications_processed: totalApplications ?? 0,
    total_approved_loans: totalApproved ?? 0,
    total_rejected_loans: totalRejected ?? 0,
    total_active_loans: totalActive ?? 0,
    total_completed_loans: totalCompleted ?? 0,
    total_collections_managed: totalCollections ?? 0,
  });
}

// ── [moved from functions/kpi-rider/index.ts] ───────────────────────────────
async function handleRider(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.RIDER);
  if (roleCheck) return roleCheck;

  const db = getAdminClient();
  const riderId = authResult.id;

  const [
    { count: totalAssigned },
    { count: totalCompleted },
    { count: totalFailed },
    { count: totalCiAssigned },
    { count: totalCiCompleted },
  ] = await Promise.all([
    db.from('collection_assignments').select('*', { count: 'exact', head: true })
      .eq('rider_id', riderId),
    db.from('collection_assignments').select('*', { count: 'exact', head: true })
      .eq('rider_id', riderId).eq('status', 'completed'),
    db.from('collection_assignments').select('*', { count: 'exact', head: true })
      .eq('rider_id', riderId).eq('status', 'failed'),
    db.from('credit_investigations').select('*', { count: 'exact', head: true })
      .eq('rider_id', riderId),
    db.from('credit_investigations').select('*', { count: 'exact', head: true })
      .eq('rider_id', riderId).eq('status', 'completed'),
  ]);

  const { data: paymentData } = await db
    .from('payments')
    .select('amount')
    .eq('recorded_by', riderId)
    .eq('status', 'verified');

  const totalCollected = (paymentData ?? []).reduce(
    (sum: number, p) => sum + Number(p.amount), 0
  );

  return jsonResponse({
    total_assigned_collections: totalAssigned ?? 0,
    total_completed_collections: totalCompleted ?? 0,
    total_failed_collections: totalFailed ?? 0,
    total_amount_collected: totalCollected,
    total_ci_assignments: totalCiAssigned ?? 0,
    total_ci_completed: totalCiCompleted ?? 0,
  });
}

// ── [moved from functions/kpi-lender/index.ts] ──────────────────────────────
async function handleLender(req: Request) {
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
    .select('id, principal_amount')
    .eq('lender_id', lenderId)
    .in('status', ['active', 'approved', 'completed', 'overdue']);

  const financials = await getLoanFinancialsBatch(
    db,
    (loanData ?? []).map((l) => l.id),
  );

  const { data: paymentData } = await db
    .from('payments')
    .select('amount, loan_schedules!inner(loan_id, loans!inner(lender_id))')
    .eq('loan_schedules.loans.lender_id', lenderId)
    .eq('status', 'verified');

  const { data: penaltyData } = await db
    .from('penalty_logs')
    .select('penalty_amount, loans!penalty_logs_loan_id_fkey!inner(lender_id)')
    .eq('loans.lender_id', lenderId);

  const { data: accountUpgradeProfile } = await db
    .from('lender_profiles')
    .select('account_upgrade_status')
    .eq('id', lenderId)
    .single();

  let totalBorrowed = 0, totalOutstanding = 0, totalInterestPaid = 0;
  (loanData ?? []).forEach((l) => {
    totalBorrowed += Number(l.principal_amount);
    totalOutstanding += Number(financials[l.id]?.outstanding_balance ?? 0);
  });

  let totalPaid = 0;
  (paymentData ?? []).forEach((p) => { totalPaid += Number(p.amount); });

  let totalPenaltiesPaid = 0;
  (penaltyData ?? []).forEach((p) => { totalPenaltiesPaid += Number(p.penalty_amount); });

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
    account_upgrade_status: accountUpgradeProfile?.account_upgrade_status ?? 'not_submitted',
  });
}