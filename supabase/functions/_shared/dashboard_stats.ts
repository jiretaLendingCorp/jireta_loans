// supabase/functions/_shared/dashboard_stats.ts
//
// Shared computation of the Head Manager dashboard KPIs. This is the SINGLE
// source of truth for "what the Head Manager dashboard shows", used by:
//   • kpi-view?fn=head-manager (the dashboard itself)
//   • ai-dashboard-insights (AI analysis of the same verified numbers)
//
// Keeping one implementation guarantees the AI always analyzes the exact same
// stats the dashboard renders — there is no duplicated or divergent logic.
//
// BUSINESS RULES — MONTHLY vs LIFETIME
// ─────────────────────────────────────────────────────────────────────────────
// Head Manager dashboard is MONTHLY by default (isMonthly=true when ?month=YYYY-MM or ?period=monthly).
// LIFETIME (no month param) is kept for backwards-compatibility / audit but UI defaults to monthly.
// When isMonthly:
//   • All count KPIs = activity INSIDE the selected month only (created_at in [monthStart, monthEndNext)).
//     This answers "what happened THIS month?" not "what is the all-time total?".
//   • User stats (employees/riders/lenders) = NEW Registrations that month (hiring velocity), not cumulative headcount.
//   • Loan counts = loans whose created_at is in month and status matches.
//   • Financials: released/outstanding/interest = principal/interest of loans originated in month (subset loanRows).
//     Collected = payments with paid_at in month; penalties = penalty_logs applied_at in month.
//     Revenue = interest + penalties. Outstanding = sum outstanding of monthly loan subset.
//   • monthly_series = last 6 months ENDING at selected month, so drill-down stays in context.
//   • loanStatusBreakdown & pendingBucket = distribution of loans created in month only.
// When isMonthly==false: all metrics are LIFETIME cumulative (legacy).
// ─────────────────────────────────────────────────────────────────────────────
import { getLoanFinancialsBatch } from './loan_financials.ts';
import type { DbClient } from './types.ts';

export interface HeadManagerStatsParams {
  /** YYYY-MM */
  month?: string | null;
  /** 'monthly' */
  period?: string | null;
}

/** Parse the month/period request params into a normalized filter. */
export function parseMonthlyFilter(params: HeadManagerStatsParams): {
  monthStart: Date | null;
  monthEndNext: Date | null;
  isMonthly: boolean;
  selectedMonth: string;
  isoStart: string | null;
  isoEnd: string | null;
} {
  const monthParam = params.month ?? null;
  const periodParam = params.period ?? null;
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
  return { monthStart, monthEndNext, isMonthly, selectedMonth, isoStart, isoEnd };
}

/**
 * Computes the Head Manager dashboard KPIs — the exact payload the dashboard
 * renders (and the AI analyzes). Aggregated, no PII.
 */
export async function getHeadManagerDashboardStats(
  db: DbClient,
  params: HeadManagerStatsParams = {},
): Promise<Record<string, unknown>> {
  const { monthStart, isMonthly, selectedMonth, isoStart, isoEnd } =
    parseMonthlyFilter(params);

  // ── Part 1: count queries ───────────────────────────────────────────────
  // Build each head query with optional date range. Users filtered on
  // created_at in month (new this month).
  const buildCounts = async () => {
    const qHeadManager = (() => {
      let q: any = db.from('users').select('*, roles!users_role_id_fkey!inner(name)', { count: 'exact', head: true }).eq('roles.name', 'head_manager').neq('account_status', 'archived');
      if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!);
      return q;
    })();
    const qEmp = (() => {
      let q: any = db.from('users').select('*, roles!users_role_id_fkey!inner(name)', { count: 'exact', head: true }).eq('roles.name', 'employee').neq('account_status', 'archived');
      if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!);
      return q;
    })();
    const qRider = (() => {
      let q: any = db.from('users').select('*, roles!users_role_id_fkey!inner(name)', { count: 'exact', head: true }).eq('roles.name', 'rider').neq('account_status', 'archived');
      if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!);
      return q;
    })();
    const qLender = (() => {
      let q: any = db.from('users').select('*, roles!users_role_id_fkey!inner(name)', { count: 'exact', head: true }).eq('roles.name', 'lender').neq('account_status', 'archived');
      if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!);
      return q;
    })();
    const qApps = (() => {
      let q: any = db.from('loans').select('*', { count: 'exact', head: true });
      if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!);
      return q;
    })();
    const qApproved = (() => {
      let q: any = db.from('loans').select('*', { count: 'exact', head: true }).in('status', ['approved', 'active', 'completed']);
      if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!);
      return q;
    })();
    const qRejected = (() => {
      let q: any = db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'rejected');
      if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!);
      return q;
    })();
    const qActive = (() => {
      let q: any = db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'active');
      if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!);
      return q;
    })();
    const qCompleted = (() => {
      let q: any = db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'completed');
      if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!);
      return q;
    })();
    const qOverdue = (() => {
      let q: any = db.from('loans').select('*', { count: 'exact', head: true }).eq('status', 'overdue');
      if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!);
      return q;
    })();
    const qCi = (() => {
      let q: any = db.from('credit_investigations').select('*', { count: 'exact', head: true });
      if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!);
      return q;
    })();
    const qReports = (() => {
      let q: any = db.from('reports').select('*', { count: 'exact', head: true });
      if (isMonthly) q = q.gte('created_at', isoStart!).lt('created_at', isoEnd!);
      return q;
    })();
    const qPendingUpgrade = (() => {
      let q: any = db.from('lender_profiles').select('*', { count: 'exact', head: true }).eq('account_upgrade_status', 'submitted');
      if (isMonthly) q = q.gte('updated_at', isoStart!).lt('updated_at', isoEnd!);
      return q;
    })();
    const qCollTx = (() => {
      let q: any = db.from('payments').select('*', { count: 'exact', head: true }).eq('status', 'verified');
      if (isMonthly) q = q.gte('paid_at', isoStart!).lt('paid_at', isoEnd!);
      return q;
    })();
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

  // ── Part 2: financial/trend queries in parallel ────────────────────────
  // Loan subset for financials — filtered to month when isMonthly.
  let loanRowsQuery: any = db.from('loans').select('id, principal_amount, created_at').in('status', ['active', 'completed', 'overdue']);
  if (isMonthly) loanRowsQuery = loanRowsQuery.gte('created_at', isoStart!).lt('created_at', isoEnd!);

  let paymentsQuery: any = db.from('payments').select('amount, payment_method, paid_at').eq('status', 'verified');
  if (isMonthly) paymentsQuery = paymentsQuery.gte('paid_at', isoStart!).lt('paid_at', isoEnd!);

  let penaltiesQuery: any = db.from('penalty_logs').select('penalty_amount, applied_at');
  if (isMonthly) penaltiesQuery = penaltiesQuery.gte('applied_at', isoStart!).lt('applied_at', isoEnd!);

  // Trend series — only records within the 6-month window to avoid full scans.
  const trendAnchor = isMonthly && monthStart ? new Date(monthStart) : new Date();
  const trendStart = new Date(Date.UTC(trendAnchor.getFullYear(), trendAnchor.getMonth() - 5, 1));
  const trendEnd = new Date(Date.UTC(trendAnchor.getFullYear(), trendAnchor.getMonth() + 1, 1));
  const trendIsoStart = trendStart.toISOString();
  const trendIsoEnd = trendEnd.toISOString();
  const trendLoansRawP = db.from('loans').select('created_at, status, principal_amount').gte('created_at', trendIsoStart).lt('created_at', trendIsoEnd);
  const trendDisbursementsP = db.from('disbursements').select('disbursed_at, amount').eq('status', 'completed').gte('disbursed_at', trendIsoStart).lt('disbursed_at', trendIsoEnd);
  const trendPaymentsP = db.from('payments').select('paid_at, amount').eq('status', 'verified').gte('paid_at', trendIsoStart).lt('paid_at', trendIsoEnd);

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

  // Financials depends on loanRows — compute after the parallel batch resolves.
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

  // ── Part 3: 6-month monthly series (full window for trend context) ─────
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

  // ── Part 4: loan portfolio breakdown by status (donut) ────────────────
  const sourceForBreakdown = isMonthly ? trendLoansMonthlyFiltered : trendLoans;
  const loanStatusBreakdown: Record<string, number> = {};
  (sourceForBreakdown ?? []).forEach((r: { status: string }) => {
    const s = (r.status ?? 'unknown') as string;
    loanStatusBreakdown[s] = (loanStatusBreakdown[s] ?? 0) + 1;
  });
  const knownStatuses = [
    'pending', 'under_review', 'ci_required', 'ci_assigned', 'ci_completed',
    'approved', 'active', 'completed', 'rejected', 'cancelled', 'overdue',
  ];
  for (const s of knownStatuses) {
    if (!(s in loanStatusBreakdown)) loanStatusBreakdown[s] = 0;
  }
  const pendingBucket = (loanStatusBreakdown['pending'] ?? 0) +
    (loanStatusBreakdown['under_review'] ?? 0) +
    (loanStatusBreakdown['ci_required'] ?? 0) +
    (loanStatusBreakdown['ci_assigned'] ?? 0) +
    (loanStatusBreakdown['ci_completed'] ?? 0) +
    (loanStatusBreakdown['approved'] ?? 0) +
    (loanStatusBreakdown['cancelled'] ?? 0);

  return {
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
    selected_month: isMonthly ? selectedMonth : null,
    is_monthly: isMonthly,
    period: isMonthly ? 'monthly' : 'lifetime',
  };
}