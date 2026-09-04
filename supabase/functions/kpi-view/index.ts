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
// BUSINESS RULES — MONTHLY vs LIFETIME
// ─────────────────────────────────────────────────────────────────────────────
// Head Manager dashboard is MONTHLY by default (isMonthly=true when ?month=YYYY-MM or ?period=monthly).
// LIFETIME (no month param) is kept for backwards-compatibility / audit but UI defaults to monthly.
// When isMonthly:
//   • All count KPIs = activity INSIDE the selected month only (created_at in [monthStart, monthEndNext)).
//     This answers "what happened THIS month?" not "what is the all-time total?".
//   • User stats (employees/riders/lenders) = NEW Registrations that month (hiring velocity), not cumulative headcount.
//     If you need headcount snapshot (active at month end), use separate analytics or remove the date filter.
//   • Loan counts (applications/approved/rejected/active/completed/overdue) = loans whose created_at is in month
//     and status matches. E.g. "Approved Loans (monthly)" = loans created in month that ended up approved/active/completed.
//   • Financials: released/outstanding/interest = principal/interest of loans originated in month (subset loanRows).
//     Collected = payments with paid_at in month; penalties = penalty_logs applied_at in month.
//     Revenue = interest (of monthly loans) + penalties (of month). Outstanding = sum outstanding of monthly loan subset.
//   • CI / Reports / Pending Upgrade / Collection Tx = records created/updated in month.
//   • monthly_series = last 6 months ENDING at selected month (not always current month), so drill-down stays in context.
//   • loanStatusBreakdown & pendingBucket = distribution of loans created in month only (so the donut reflects monthly pipeline).
// When isMonthly==false (no month query): all metrics are LIFETIME cumulative (legacy) — every record ever created.
// ─────────────────────────────────────────────────────────────────────────────
async function handleHeadManager(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
  if (roleCheck) return roleCheck;

  const db = getAdminClient();
  const url = new URL(req.url);
  const monthParam = url.searchParams.get('month'); // YYYY-MM
  const periodParam = url.searchParams.get('period');
  let monthStart: Date | null = null;
  let monthEndNext: Date | null = null;
  let isMonthly = false;
  let selectedMonth = '';
  if (monthParam && /^\d{4}-\d{2}$/.test(monthParam)) {
    const [yy, mm] = monthParam.split('-').map(Number);
    if (mm >= 1 && mm <= 12) {
      monthStart = new Date(Date.UTC(yy, mm - 1, 1, 0, 0, 0));
      monthEndNext = new Date(Date.UTC(yy, mm, 1, 0, 0, 0));
      isMonthly = true;
      selectedMonth = monthParam;
    }
  } else if (periodParam === 'monthly') {
    const now = new Date();
    monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
    monthEndNext = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1));
    isMonthly = true;
    selectedMonth = `${monthStart.getUTCFullYear()}-${String(monthStart.getUTCMonth() + 1).padStart(2, '0')}`;
  }
  const isoStart = monthStart?.toISOString() ?? null;
  const isoEnd = monthEndNext?.toISOString() ?? null;

  // Helper to add monthly date filter on created_at / generated_at / paid_at as appropriate.
  // For lifetime mode we use the base query untouched.
  const buildCounts = async () => {
    // Build each head query with optional date range. Users filtered on created_at in month (new this month).
    const qHeadManager = (() => { let q: any = db.from('users').select('*, roles!users_role_id_fkey!inner(name)', { count: 'exact', head: true }).eq('roles.name', 'head_manager').neq('account_status', 'archived'); if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!); return q; })();
    const qEmp = (() => { let q: any = db.from('users').select('*, roles!users_role_id_fkey!inner(name)', { count: 'exact', head: true }).eq('roles.name', 'employee').neq('account_status', 'archived'); if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!); return q; })();
    const qRider = (() => { let q: any = db.from('users').select('*, roles!users_role_id_fkey!inner(name)', { count: 'exact', head: true }).eq('roles.name', 'rider').neq('account_status', 'archived'); if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!); return q; })();
    const qLender = (() => { let q: any = db.from('users').select('*, roles!users_role_id_fkey!inner(name)', { count: 'exact', head: true }).eq('roles.name', 'lender').neq('account_status', 'archived'); if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!); return q; })();
    const qApps = (() => { let q: any = db.from('loans').select('*', { count: 'exact', head: true }); if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!); return q; })();
    const qApproved = (() => { let q: any = db.from('loans').select('*', { count: 'exact', head: true }).in('status', ['approved', 'active', 'completed']); if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!); return q; })();
    const qRejected = (() => { let q: any = db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'rejected'); if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!); return q; })();
    const qActive = (() => { let q: any = db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'active'); if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!); return q; })();
    const qCompleted = (() => { let q: any = db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'completed'); if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!); return q; })();
    const qOverdue = (() => { let q: any = db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'overdue'); if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!); return q; })();
    const qCi = (() => { let q: any = db.from('credit_investigations').select('*', { count: 'exact', head: true }); if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!); return q; })();
    const qReports = (() => { let q: any = db.from('reports').select('*', { count: 'exact', head: true }); if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!); return q; })(); // use created_at to avoid missing generated_at index
    const qPendingUpgrade = (() => { let q: any = db.from('lender_profiles').select('*', { count: 'exact', head: true }).eq('account_upgrade_status', 'submitted'); if (isMonthly) q = q.gte('updated_at', isoStart!).lt('updated_at', isoEnd!); return q; })();
    const qCollTx = (() => { let q: any = db.from('payments').select('*', { count: 'exact', head: true }).eq('status', 'verified'); if (isMonthly) q = q.gte('paid_at', isoStart!).lt('paid_at', isoEnd!); return q; })();
    return await Promise.all([qHeadManager, qEmp, qRider, qLender, qApps, qApproved, qRejected, qActive, qCompleted, qOverdue, qCi, qReports, qPendingUpgrade, qCollTx]);
  };

  const [
    { count: totalHeadManagers },
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
  ] = await buildCounts();

  // ── Fire all independent queries in parallel ───────────────────────────
  // Loan subset for financials — filtered to month when isMonthly (loans originated that month)
  let loanRowsQuery: any = db.from('loans').select('id, principal_amount, created_at').in('status', ['active', 'completed', 'overdue']);
  if (isMonthly) loanRowsQuery = loanRowsQuery.gte('created_at', isoStart!).lt('created_at', isoEnd!);

  // Payments / penalties — monthly filtered on paid_at / applied_at
  let paymentsQuery: any = db.from('payments').select('amount, payment_method, paid_at').eq('status', 'verified');
  if (isMonthly) paymentsQuery = paymentsQuery.gte('paid_at', isoStart!).lt('paid_at', isoEnd!);

  let penaltiesQuery: any = db.from('penalty_logs').select('penalty_amount, applied_at');
  if (isMonthly) penaltiesQuery = penaltiesQuery.gte('applied_at', isoStart!).lt('applied_at', isoEnd!);

  // Trend series queries — independent, no dependencies
  // Only fetch records within the 6-month trend window to avoid full table scans.
  const trendAnchor = isMonthly && monthStart ? new Date(monthStart) : new Date();
  const trendStart = new Date(Date.UTC(trendAnchor.getFullYear(), trendAnchor.getMonth() - 5, 1));
  const trendEnd = new Date(Date.UTC(trendAnchor.getFullYear(), trendAnchor.getMonth() + 1, 1));
  const trendIsoStart = trendStart.toISOString();
  const trendIsoEnd = trendEnd.toISOString();
  const trendLoansRawP = db.from('loans').select('created_at, status, principal_amount').gte('created_at', trendIsoStart).lt('created_at', trendIsoEnd);
  const trendDisbursementsP = db.from('disbursements').select('disbursed_at, amount').eq('status', 'completed').gte('disbursed_at', trendIsoStart).lt('disbursed_at', trendIsoEnd);
  const trendPaymentsP = db.from('payments').select('paid_at, amount').eq('status', 'verified').gte('paid_at', trendIsoStart).lt('paid_at', trendIsoEnd);

  // Run all 6 queries in parallel
  const [
    { data: loanRows },
    { data: payments },
    { data: penalties },
    { data: trendLoansRaw },
    { data: trendDisbursements },
    { data: trendPayments },
  ] = await Promise.all([
    loanRowsQuery,
    paymentsQuery,
    penaltiesQuery,
    trendLoansRawP,
    trendDisbursementsP,
    trendPaymentsP,
  ]);

  // Financials depends on loanRows — compute after parallel batch resolves
  const financials = await getLoanFinancialsBatch(
    db,
    (loanRows ?? []).map((l: any) => l.id),
  );

  let totalReleased = 0, totalOutstanding = 0, totalInterest = 0;
  (loanRows ?? []).forEach((l: any) => {
    const fin = (financials as any)[l.id] ?? null;
    totalReleased += Number(l.principal_amount);
    totalOutstanding += Number(fin?.outstanding_balance ?? 0);
    totalInterest += Number(fin?.interest_amount ?? 0);
  });

  let totalCollected = 0;
  (payments ?? []).forEach((p: any) => { totalCollected += Number(p.amount); });

  let totalPenalties = 0;
  (penalties ?? []).forEach((p: any) => { totalPenalties += Number(p.penalty_amount); });

  // For isMonthly we restrict trendLoans to subset? No — monthlySeries still shows full 6-month history for context.
  // But loanStatusBreakdown should reflect only selectedMonth's loans when monthly, so we filter a copy.
  const trendLoans = trendLoansRaw;
  const trendLoansMonthlyFiltered = isMonthly && isoStart && isoEnd
    ? (trendLoansRaw ?? []).filter((l: any) => l.created_at && new Date(l.created_at).getTime() >= new Date(isoStart!).getTime() && new Date(l.created_at).getTime() < new Date(isoEnd!).getTime())
    : trendLoansRaw;

  const monthlySeries: Array<{
    month: string;
    applications: number;
    released: number;
    collected: number;
  }> = [];
  // Determine anchor month for series (selectedMonth end vs now)
  const anchor = isMonthly && monthStart ? new Date(monthStart) : new Date();
  for (let i = 5; i >= 0; i--) {
    const d = new Date(anchor.getFullYear(), anchor.getMonth() - i, 1);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    const next = new Date(d.getFullYear(), d.getMonth() + 1, 1);
    const inRange = (ts: string | null | undefined) => {
      if (!ts) return false;
      const t = new Date(ts).getTime();
      return t >= d.getTime() && t < next.getTime();
    };
    monthlySeries.push({
      month: key,
      applications: (trendLoans ?? []).filter((l: any) => inRange(l.created_at)).length,
      released: (trendDisbursements ?? [])
        .filter((x: any) => inRange(x.disbursed_at))
        .reduce((s: number, x: any) => s + Number(x.amount), 0),
      collected: (trendPayments ?? [])
        .filter((p: any) => inRange(p.paid_at))
        .reduce((s: number, p: any) => s + Number(p.amount), 0),
    });
  }

  // ── Loan portfolio breakdown by status (for interactive donut drill-down) ─
  // Monthly mode: donut reflects ONLY loans created in selected month; lifetime: all loans.
  const sourceForBreakdown = isMonthly ? trendLoansMonthlyFiltered : trendLoans;
  const loanStatusBreakdown: Record<string, number> = {};
  (sourceForBreakdown ?? []).forEach((r: { status: string }) => {
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
    total_head_managers: totalHeadManagers ?? 0,
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
    // Monthly metadata — frontend uses this to switch labels & show "May 2026 — Monthly View"
    selected_month: isMonthly ? selectedMonth : null,
    is_monthly: isMonthly,
    period: isMonthly ? 'monthly' : 'lifetime',
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
  (loanData ?? []).forEach((l: any) => {
    totalBorrowed += Number(l.principal_amount);
    totalOutstanding += Number((financials as any)[l.id]?.outstanding_balance ?? 0);
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
    account_upgrade_status: accountUpgradeProfile?.account_upgrade_status ?? 'not_submitted',
  });
}