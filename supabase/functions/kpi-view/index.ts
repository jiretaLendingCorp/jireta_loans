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
import { getHeadManagerDashboardStats } from '../_shared/dashboard_stats.ts';
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
// The KPI computation itself now lives in _shared/dashboard_stats.ts so the
// AI insights function can analyze the EXACT same numbers the dashboard
// renders (single source of truth, no duplicated query logic).
async function handleHeadManager(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
  if (roleCheck) return roleCheck;

  const db = getAdminClient();
  const url = new URL(req.url);
  const data = await getHeadManagerDashboardStats(db, {
    month: url.searchParams.get('month'),
    period: url.searchParams.get('period'),
  });
  return jsonResponse(data);
}

// ── [moved from functions/kpi-employee/index.ts] ────────────────────────────
// MONTHLY: ?month=YYYY-MM filters all KPIs to activity INSIDE that month
// (same semantics as head-manager dashboard). No param = lifetime (legacy).
async function handleEmployee(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const db = getAdminClient();
  const empId = authResult.id;
  const url = new URL(req.url);
  const monthParam = url.searchParams.get('month');

  let isoStart: string | null = null;
  let isoEnd: string | null = null;
  let isMonthly = false;
  let selectedMonth = '';
  if (monthParam && /^\d{4}-\d{2}$/.test(monthParam)) {
    const [yy, mm] = monthParam.split('-').map(Number);
    if (mm >= 1 && mm <= 12) {
      isoStart = new Date(Date.UTC(yy, mm - 1, 1, 0, 0, 0)).toISOString();
      isoEnd = new Date(Date.UTC(yy, mm, 1, 0, 0, 0)).toISOString();
      isMonthly = true;
      selectedMonth = monthParam;
    }
  }

  const applyMonth = (q: any, col = 'created_at') => {
    if (isMonthly && isoStart && isoEnd) q = q.gte(col, isoStart).lt(col, isoEnd);
    return q;
  };

  const [
    { count: totalLenders },
    { count: totalApplications },
    { count: totalApproved },
    { count: totalRejected },
    { count: totalActive },
    { count: totalCompleted },
    { count: totalCollections },
  ] = await Promise.all([
    applyMonth(db.from('users').select('*', { count: 'exact', head: true })
      .eq('created_by', empId).eq('roles.name', 'lender')),
    applyMonth(db.from('loans').select('*, in_office_applications!fk_loans_in_office(created_by)', { count: 'exact', head: true })
      .eq('in_office_applications.created_by', empId)),
    applyMonth(db.from('loans').select('*, in_office_applications!fk_loans_in_office(created_by)', { count: 'exact', head: true })
      .eq('in_office_applications.created_by', empId).in('status', ['approved', 'active', 'completed'])),
    applyMonth(db.from('loans').select('*, in_office_applications!fk_loans_in_office(created_by)', { count: 'exact', head: true })
      .eq('in_office_applications.created_by', empId).eq('status', 'rejected')),
    applyMonth(db.from('loans').select('*, in_office_applications!fk_loans_in_office(created_by)', { count: 'exact', head: true })
      .eq('in_office_applications.created_by', empId).eq('status', 'active')),
    applyMonth(db.from('loans').select('*, in_office_applications!fk_loans_in_office(created_by)', { count: 'exact', head: true })
      .eq('in_office_applications.created_by', empId).eq('status', 'completed')),
    applyMonth(db.from('collection_assignments').select('*', { count: 'exact', head: true })
      .eq('assigned_by', empId)),
  ]);

  return jsonResponse({
    total_lenders_managed: totalLenders ?? 0,
    total_applications_processed: totalApplications ?? 0,
    total_approved_loans: totalApproved ?? 0,
    total_rejected_loans: totalRejected ?? 0,
    total_active_loans: totalActive ?? 0,
    total_completed_loans: totalCompleted ?? 0,
    total_collections_managed: totalCollections ?? 0,
    selected_month: isMonthly ? selectedMonth : null,
    is_monthly: isMonthly,
    period: isMonthly ? 'monthly' : 'lifetime',
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