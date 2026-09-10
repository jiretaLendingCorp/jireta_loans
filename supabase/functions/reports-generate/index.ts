// supabase/functions/reports-generate/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// REPORT GENERATION (HEAD MANAGER ONLY)
//
// This function is the boundary between the PostgreSQL schema and the Flutter
// report UI. Every branch below returns BUSINESS-ONLY rows: human-readable
// names are resolved server-side, raw UUIDs / foreign keys / audit identifiers
// are never exposed, and every query lists its columns explicitly (no
// `SELECT *`).
//
// The sanitised row snapshot is persisted to `reports.data` so PDF / Excel
// exports and the in-app preview render the exact same clean rows.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import {
  getLoanFinancialsBatch,
  getLoanDisbursementsBatch,
} from '../_shared/loan_financials.ts';
import { embedAsObject } from '../_shared/types.ts';

// ── Report filter whitelists ────────────────────────────────────────────────
// Out-of-list values are dropped so a bad filter can never widen a report into
// an unintended status/method bucket.
const LOAN_STATUSES = new Set([
  'pending', 'under_review', 'ci_required', 'ci_assigned', 'ci_completed',
  'approved', 'active', 'completed', 'overdue', 'rejected', 'cancelled',
]);
const COLLECTION_STATUSES = new Set([
  'requested', 'assigned', 'accepted', 'declined', 'in_progress',
  'completed', 'failed',
]);
const PAYMENT_METHODS = new Set(['gcash', 'office_cash', 'rider_collection']);
const DISBURSEMENT_METHODS = new Set(['gcash', 'office_cash', 'rider_delivery']);
const CI_STATUSES = new Set([
  'pending', 'assigned', 'accepted', 'declined', 'in_progress', 'completed',
]);

/** Accepts only an `YYYY-MM-DD` calendar date (or null for "no filter"). */
function dateParam(value: unknown): string | null {
  if (value == null || value === '') return null;
  if (typeof value !== 'string') return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  return value;
}

function dayStart(date: string): string {
  return `${date}T00:00:00.000Z`;
}

function dayEnd(date: string): string {
  return `${date}T23:59:59.999Z`;
}

/** Inclusive [from, to] bounds, defaulting to the full history. */
function bounds(params: Record<string, string>): { from: string; to: string } {
  const today = new Date().toISOString().slice(0, 10);
  return {
    from: dayStart(dateParam(params.date_from) ?? '2000-01-01'),
    to: dayEnd(dateParam(params.date_to) ?? today),
  };
}

type Db = ReturnType<typeof getAdminClient>;

function name(first?: string | null, last?: string | null): string {
  return [first, last].filter(Boolean).join(' ').trim() || '—';
}

// ══ ROW BUILDERS — one clean, flat, business-facing DTO per report ═════════
async function buildLoanSummary(
  db: Db,
  params: Record<string, string>,
): Promise<Record<string, unknown>[]> {
  const { from, to } = bounds(params);
  const status = params.status && LOAN_STATUSES.has(params.status)
    ? params.status
    : null;

  // `id` is selected internally ONLY to key the financial/disbursement lookups.
  // It never leaves this function in a report row.
  let query = db.from('loans').select(
    `id, loan_number, principal_amount, interest_rate, payment_frequency,
     term_periods, status, created_at,
     lender:lender_profiles!loans_lender_id_fkey(
       users!lender_profiles_id_fkey(first_name, last_name, phone_number)
     )`,
  );
  if (status) query = query.eq('status', status);
  query = query.gte('created_at', from).lte('created_at', to);

  const { data, error } = await query;
  if (error) throw new Error(`loan_summary query failed: ${error.message}`);
  const rows = (data ?? []) as unknown as Array<{
    id: string;
    loan_number: string;
    principal_amount: string | number;
    interest_rate: string | number;
    payment_frequency: string;
    term_periods: number | null;
    status: string;
    created_at: string;
    lender: { users?: { first_name?: string; last_name?: string; phone_number?: string } | null } | null;
  }>;

  const [finMap, disbMap] = await Promise.all([
    getLoanFinancialsBatch(db, rows.map((r) => r.id)),
    getLoanDisbursementsBatch(db, rows.map((r) => r.id)),
  ]);

  return rows.map((r) => {
    const lender = embedAsObject(r.lender);
    const lenderUser = lender ? embedAsObject(lender.users) : null;
    const fin = finMap[r.id] ?? { total_payable: null, outstanding_balance: null };
    const disb = disbMap[r.id] ?? null;
    return {
      loanNumber: r.loan_number,
      lenderName: name(lenderUser?.first_name, lenderUser?.last_name),
      phoneNumber: lenderUser?.phone_number ?? null,
      principalAmount: r.principal_amount,
      interestRate: r.interest_rate,
      totalPayable: fin.total_payable ?? null,
      outstandingBalance: fin.outstanding_balance ?? null,
      paymentFrequency: r.payment_frequency,
      installments: r.term_periods,
      status: r.status,
      appliedAt: r.created_at,
      disbursedAt: disb?.disbursed_at ?? null,
    };
  });
}

const LOAN_EMBED = `loan_number,
  lender_profiles!loans_lender_id_fkey(
    users!lender_profiles_id_fkey(first_name, last_name)
  )`;

function resolvePaymentLoan(
  scheduleEmbed: any,
  assignmentEmbed: any,
): { loan_number?: string; lender_profiles?: any } | null {
  const schedule = embedAsObject<{ loan?: unknown }>(scheduleEmbed);
  if (schedule) {
    const loan = embedAsObject<{ loan_number?: string; lender_profiles?: any }>(schedule.loan as any);
    if (loan) return loan;
  }
  const assignment = embedAsObject<{ loan_schedule?: unknown }>(assignmentEmbed);
  if (assignment) {
    const viaSchedule = embedAsObject<{ loan?: any }>(assignment.loan_schedule as any);
    const loan = viaSchedule
      ? embedAsObject<{ loan_number?: string; lender_profiles?: any }>(viaSchedule.loan as any)
      : null;
    if (loan) return loan;
  }
  return null;
}

async function buildPaymentReport(
  db: Db,
  params: Record<string, string>,
): Promise<Record<string, unknown>[]> {
  const { from, to } = bounds(params);
  const method = params.method && PAYMENT_METHODS.has(params.method)
    ? params.method
    : null;

  let query = db.from('payments').select(
    `amount, payment_method, status, xendit_reference, paid_at, created_at,
     schedule:loan_schedules!payments_loan_schedule_id_fkey(
       loan:loans(${LOAN_EMBED})
     ),
     assignment:collection_assignments!payments_collection_assignment_id_fkey(
       loan_schedule:loan_schedules(
         loan:loans(${LOAN_EMBED})
       )
     )`,
  ).eq('status', 'verified');
  if (method) query = query.eq('payment_method', method);
  query = query.gte('created_at', from).lte('created_at', to);

  const { data, error } = await query;
  if (error) throw new Error(`payment_report query failed: ${error.message}`);

  return ((data ?? []) as unknown as Array<Record<string, any>>).map((p) => {
    const loan = resolvePaymentLoan(p.schedule, p.assignment);
    const lender = loan ? embedAsObject<{ users?: { first_name?: string; last_name?: string } }>(loan.lender_profiles as any) : null;
    const lenderUser = lender ? embedAsObject(lender.users) : null;
    return {
      referenceNumber: p.xendit_reference ?? null,
      loanNumber: loan?.loan_number ?? '—',
      lenderName: name(lenderUser?.first_name, lenderUser?.last_name),
      amount: p.amount,
      paymentMethod: p.payment_method,
      status: p.status,
      paymentDate: p.paid_at ?? p.created_at,
    };
  });
}

async function buildCollectionReport(
  db: Db,
  params: Record<string, string>,
): Promise<Record<string, unknown>[]> {
  const { from, to } = bounds(params);
  const status = params.status && COLLECTION_STATUSES.has(params.status)
    ? params.status
    : null;

  let query = db.from('collection_assignments').select(
    `status, collection_type, amount_collected, requested_amount, created_at, completed_at,
     rider:rider_profiles(users!rider_profiles_id_fkey(first_name, last_name)),
     loan_schedule:loan_schedules(
       due_date, amount_due,
       loan:loans(${LOAN_EMBED})
     )`,
  );
  if (status) query = query.eq('status', status);
  query = query.gte('created_at', from).lte('created_at', to);

  const { data, error } = await query;
  if (error) throw new Error(`collection_report query failed: ${error.message}`);

  return ((data ?? []) as unknown as Array<Record<string, any>>).map((r) => {
    const rider = embedAsObject<{ users?: { first_name?: string; last_name?: string } }>(r.rider);
    const riderUser = rider ? embedAsObject(rider.users) : null;
    const schedule = embedAsObject<{ due_date?: string; amount_due?: unknown; loan?: unknown }>(r.loan_schedule);
    const loan = schedule
      ? embedAsObject<{ loan_number?: string; lender_profiles?: any }>(schedule.loan as any)
      : null;
    const lender = loan ? embedAsObject<{ users?: { first_name?: string; last_name?: string } }>(loan.lender_profiles as any) : null;
    const lenderUser = lender ? embedAsObject(lender.users) : null;
    return {
      loanNumber: loan?.loan_number ?? '—',
      lenderName: name(lenderUser?.first_name, lenderUser?.last_name),
      riderName: name(riderUser?.first_name, riderUser?.last_name),
      collectionType: r.collection_type === 'office' ? 'Office' : 'Rider',
      amountCollected: r.amount_collected ?? null,
      requestedAmount: r.requested_amount ?? null,
      dueDate: schedule?.due_date ?? null,
      status: r.status,
      collectedAt: r.completed_at ?? null,
    };
  });
}

async function buildLenderReport(
  db: Db,
  params: Record<string, string>,
  upgradeOnly: boolean,
): Promise<Record<string, unknown>[]> {
  const { from, to } = bounds(params);

  let query = db.from('users').select(
    `first_name, last_name, phone_number, account_status, created_at,
     roles!users_role_id_fkey!inner(name),
     lender_profiles!lender_profiles_id_fkey(account_upgrade_status)`,
  ).eq('roles.name', 'lender');
  if (upgradeOnly) {
    query = query.not('lender_profiles.account_upgrade_status', 'eq', 'not_submitted');
  }
  query = query.gte('created_at', from).lte('created_at', to);
  query = query.order('created_at', { ascending: false });

  const { data, error } = await query;
  if (error) throw new Error('lender_report query failed');

  return ((data ?? []) as unknown as Array<Record<string, any>>).map((r) => {
    const profile = embedAsObject<{ account_upgrade_status?: string }>(r.lender_profiles);
    return {
      lenderName: name(r.first_name, r.last_name),
      phoneNumber: r.phone_number ?? '—',
      accountStatus: r.account_status,
      verificationStatus: profile?.account_upgrade_status ?? '—',
      registeredAt: r.created_at,
    };
  });
}

async function buildRiderReport(
  db: Db,
  params: Record<string, string>,
): Promise<Record<string, unknown>[]> {
  const { from, to } = bounds(params);

  const [ridersRes, ciRes, collRes] = await Promise.all([
    db.from('users').select(
      `id, first_name, last_name, phone_number, account_status,
       roles!users_role_id_fkey!inner(name),
       rider_profiles!rider_profiles_id_fkey(is_available, plate_number, vehicle_type)`,
    ).eq('roles.name', 'rider'),
    db.from('credit_investigations')
      .select('rider_id, status')
      .gte('created_at', from)
      .lte('created_at', to),
    db.from('collection_assignments')
      .select('rider_id, status, amount_collected')
      .gte('created_at', from)
      .lte('created_at', to),
  ]);
  if (ridersRes.error) throw new Error('rider_report query failed');

  const ciCounts: Record<string, { assigned: number; completed: number }> = {};
  for (const c of ciRes.data ?? []) {
    const key = String((c as { rider_id: string }).rider_id);
    const slot = ciCounts[key] ?? { assigned: 0, completed: 0 };
    slot.assigned += 1;
    if ((c as { status: string }).status === 'completed') slot.completed += 1;
    ciCounts[key] = slot;
  }
  const collCounts: Record<string, { completed: number; collected: number }> = {};
  for (const c of collRes.data ?? []) {
    const key = String((c as { rider_id: string }).rider_id);
    const slot = collCounts[key] ?? { completed: 0, collected: 0 };
    if ((c as { status: string }).status === 'completed') {
      slot.completed += 1;
      slot.collected += Number((c as { amount_collected: string | number }).amount_collected ?? 0);
    }
    collCounts[key] = slot;
  }

  return ((ridersRes.data ?? []) as unknown as Array<Record<string, any>>).map((r) => {
    const profile = embedAsObject<{ is_available?: boolean; plate_number?: string; vehicle_type?: string }>(r.rider_profiles);
    const ci = ciCounts[r.id] ?? { assigned: 0, completed: 0 };
    const coll = collCounts[r.id] ?? { completed: 0, collected: 0 };
    return {
      riderName: name(r.first_name, r.last_name),
      phoneNumber: r.phone_number ?? '—',
      vehicle: profile?.vehicle_type ?? '—',
      plateNumber: profile?.plate_number ?? '—',
      available: profile?.is_available ? 'Yes' : 'No',
      accountStatus: r.account_status,
      ciAssignments: ci.assigned,
      ciCompleted: ci.completed,
      collectionsCompleted: coll.completed,
      amountCollected: Math.round(coll.collected * 100) / 100,
    };
  });
}

async function buildEmployeeReport(
  db: Db,
  params: Record<string, string>,
): Promise<Record<string, unknown>[]> {
  const { from, to } = bounds(params);

  const { data: employees, error } = await db.from('users').select(
    `id, first_name, last_name, account_status,
     roles!users_role_id_fkey!inner(name),
     employee_profiles!employee_profiles_id_fkey(position)`,
  ).eq('roles.name', 'employee');
  if (error) throw new Error('employee_report query failed');
  const empRows = (employees ?? []) as unknown as Array<Record<string, any>>;
  const empIds = empRows.map((r) => String(r.id)).filter(Boolean);

  // Loan actions inside the window counted from the actual action columns so
  // the report shows what each employee processed, not just who is on file.
  let loanData: Array<Record<string, any>> = [];
  if (empIds.length > 0) {
    const { data: loans } = await db.from('loans')
      .select('approved_by, rejected_by')
      .gte('created_at', from)
      .lte('created_at', to);
    loanData = (loans ?? []) as unknown as Array<Record<string, any>>;
  }
  const counts = new Map<string, { approved: number; rejected: number }>();
  for (const emp of empIds) counts.set(emp, { approved: 0, rejected: 0 });
  for (const l of loanData) {
    const byId = String(l.approved_by ?? '');
    if (byId && counts.has(byId)) counts.get(byId)!.approved += 1;
    const rejId = String(l.rejected_by ?? '');
    if (rejId && counts.has(rejId)) counts.get(rejId)!.rejected += 1;
  }

  return empRows.map((r) => {
    const profile = embedAsObject<{ position?: string }>(r.employee_profiles);
    const c = counts.get(String(r.id)) ?? { approved: 0, rejected: 0 };
    return {
      employeeName: name(r.first_name, r.last_name),
      position: profile?.position ?? '—',
      accountStatus: r.account_status,
      loansApproved: c.approved,
      loansRejected: c.rejected,
    };
  });
}

async function buildOverdueReport(
  db: Db,
): Promise<Record<string, unknown>[]> {
  const { data, error } = await db.from('loans').select(
    `id, loan_number, status,
     lender:lender_profiles!loans_lender_id_fkey(
       users!lender_profiles_id_fkey(first_name, last_name, phone_number)
     ),
     schedules:loan_schedules(due_date)`,
  ).eq('status', 'overdue');
  if (error) throw new Error('overdue_report query failed');
  const rows = (data ?? []) as unknown as Array<Record<string, any>>;

  const finMap = await getLoanFinancialsBatch(
    db,
    rows.map((r) => String(r.id)),
  );
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  return rows.map((r) => {
    const lender = embedAsObject<{ users?: { first_name?: string; last_name?: string; phone_number?: string } }>(r.lender);
    const lenderUser = lender ? embedAsObject(lender.users) : null;
    const dueDates = (Array.isArray(r.schedules) ? r.schedules : [])
      .map((s: { due_date?: string }) => s.due_date)
      .filter(Boolean)
      .sort() as string[];
    const earliestDue = dueDates[0] ?? null;
    const daysOverdue = earliestDue
      ? Math.max(0, Math.floor((today.getTime() - new Date(`${earliestDue}T00:00:00`).getTime()) / 86400000))
      : null;
    return {
      loanNumber: r.loan_number,
      lenderName: name(lenderUser?.first_name, lenderUser?.last_name),
      phoneNumber: lenderUser?.phone_number ?? null,
      outstandingBalance: finMap[String(r.id)]?.outstanding_balance ?? null,
      dueDate: earliestDue,
      daysOverdue,
      status: r.status,
    };
  });
}

/** Flat monthly rows from verified payments + applied penalties. */
async function buildFinancialRows(
  db: Db,
  params: Record<string, string>,
  penaltiesOnly: boolean,
  interestOnly: boolean,
): Promise<Record<string, unknown>[]> {
  const { from, to } = bounds(params);

  const [payRes, penRes] = await Promise.all([
    db.from('payments')
      .select('amount, created_at')
      .eq('status', 'verified')
      .gte('created_at', from)
      .lte('created_at', to),
    db.from('penalty_logs')
      .select('penalty_amount, applied_at')
      .gte('applied_at', from)
      .lte('applied_at', to),
  ]);
  if (payRes.error || penRes.error) throw new Error('financial query failed');

  const payments = (payRes.data ?? []) as unknown as Array<Record<string, any>>;
  const penalties = (penRes.data ?? []) as unknown as Array<Record<string, any>>;

  if (interestOnly) {
    // Interest earned is realized per loan (principal × rate), so report it on
    // a per-loan basis rather than fabricating an allocation between principal
    // and interest inside each collected payment.
    return await buildInterestReport(db, params);
  }

  const byMonth = new Map<string, { payments: number; penalties: number }>();
  for (const p of payments) {
    const key = String(p.created_at ?? '').slice(0, 7);
    const slot = byMonth.get(key) ?? { payments: 0, penalties: 0 };
    slot.payments += Number(p.amount ?? 0);
    byMonth.set(key, slot);
  }
  for (const p of penalties) {
    const key = String(p.applied_at ?? '').slice(0, 7);
    const slot = byMonth.get(key) ?? { payments: 0, penalties: 0 };
    slot.penalties += Number(p.penalty_amount ?? 0);
    byMonth.set(key, slot);
  }

  const months = [...byMonth.keys()].sort();
  if (penaltiesOnly) {
    return months.map((m) => {
      const s = byMonth.get(m)!;
      return {
        period: m === '' ? '—' : m,
        penaltiesTotal: Math.round(s.penalties * 100) / 100,
        penaltyCount: penalties.filter((p) => String(p.applied_at ?? '').startsWith(m)).length,
      };
    });
  }
  return months.map((m) => {
    const s = byMonth.get(m)!;
    const revenue = s.payments + s.penalties;
    return {
      period: m === '' ? '—' : m,
      paymentsTotal: Math.round(s.payments * 100) / 100,
      penaltiesTotal: Math.round(s.penalties * 100) / 100,
      revenue: Math.round(revenue * 100) / 100,
      transactions:
        payments.filter((p) => String(p.created_at ?? '').startsWith(m)).length +
        penalties.filter((p) => String(p.applied_at ?? '').startsWith(m)).length,
    };
  });
}

/** Interest per loan on the books in the selected window. */
async function buildInterestReport(
  db: Db,
  params: Record<string, string>,
): Promise<Record<string, unknown>[]> {
  const { from, to } = bounds(params);
  const { data, error } = await db.from('loans').select(
    `id, loan_number, principal_amount, interest_rate,
     lender:lender_profiles!loans_lender_id_fkey(
       users!lender_profiles_id_fkey(first_name, last_name)
     )`,
  ).gte('created_at', from).lte('created_at', to);
  if (error) throw new Error('interest_report query failed');
  const rows = (data ?? []) as unknown as Array<Record<string, any>>;
  const finMap = await getLoanFinancialsBatch(db, rows.map((r) => String(r.id)));

  return rows.map((r) => {
    const lender = embedAsObject<{ users?: { first_name?: string; last_name?: string } }>(r.lender);
    const lenderUser = lender ? embedAsObject(lender.users) : null;
    const fin = finMap[String(r.id)] ?? {};
    return {
      loanNumber: r.loan_number,
      lenderName: name(lenderUser?.first_name, lenderUser?.last_name),
      principalAmount: r.principal_amount,
      interestRate: r.interest_rate,
      interestAmount: fin.interest_amount ?? null,
      totalPayable: fin.total_payable ?? null,
      outstandingBalance: fin.outstanding_balance ?? null,
    };
  });
}

async function buildAuditReport(
  db: Db,
  params: Record<string, string>,
): Promise<Record<string, unknown>[]> {
  const { from, to } = bounds(params);
  const action = params.action ? String(params.action).slice(0, 100) : null;

  let query = db.from('audit_logs').select(
    `action, table_name, created_at,
     actor:users!audit_logs_performed_by_fkey(first_name, last_name)`,
  );
  if (action) query = query.eq('action', action);
  query = query.gte('created_at', from).lte('created_at', to);
  query = query.order('created_at', { ascending: false }).limit(500);

  const { data, error } = await query;
  if (error) throw new Error('audit_report query failed');

  return ((data ?? []) as unknown as Array<Record<string, any>>).map((r) => {
    const actor = embedAsObject<{ first_name?: string; last_name?: string }>(r.actor);
    return {
      performedAt: r.created_at,
      actorName: name(actor?.first_name, actor?.last_name),
      action: r.action,
      module: r.table_name,
    };
  });
}

async function buildCiReport(
  db: Db,
  params: Record<string, string>,
): Promise<Record<string, unknown>[]> {
  const { from, to } = bounds(params);
  const status = params.status && CI_STATUSES.has(params.status)
    ? params.status
    : null;

  let query = db.from('credit_investigations').select(
    `status, created_at, completed_at, report_summary,
     rider:rider_profiles(users!rider_profiles_id_fkey(first_name, last_name)),
     loan:loans(${LOAN_EMBED})`,
  );
  if (status) query = query.eq('status', status);
  query = query.gte('created_at', from).lte('created_at', to);

  const { data, error } = await query;
  if (error) throw new Error('ci_report query failed');

  return ((data ?? []) as unknown as Array<Record<string, any>>).map((r) => {
    const rider = embedAsObject<{ users?: { first_name?: string; last_name?: string } }>(r.rider);
    const riderUser = rider ? embedAsObject(rider.users) : null;
    const loan = embedAsObject<{ loan_number?: string; lender_profiles?: any }>(r.loan as any);
    const lender = loan ? embedAsObject<{ users?: { first_name?: string; last_name?: string } }>(loan.lender_profiles as any) : null;
    const lenderUser = lender ? embedAsObject(lender.users) : null;
    return {
      loanNumber: loan?.loan_number ?? '—',
      lenderName: name(lenderUser?.first_name, lenderUser?.last_name),
      riderName: name(riderUser?.first_name, riderUser?.last_name),
      status: r.status,
      findings: r.report_summary ?? '—',
      assignedAt: r.created_at,
      completedAt: r.completed_at,
    };
  });
}

async function buildDisbursementReport(
  db: Db,
  params: Record<string, string>,
): Promise<Record<string, unknown>[]> {
  const { from, to } = bounds(params);
  const method = params.method && DISBURSEMENT_METHODS.has(params.method)
    ? params.method
    : null;

  let query = db.from('disbursements').select(
    `method, amount, status, created_at, disbursed_at,
     loan:loans(${LOAN_EMBED}),
     authorized_by_user:users!disbursements_authorized_by_fkey(first_name, last_name)`,
  );
  if (method) query = query.eq('method', method);
  query = query.gte('created_at', from).lte('created_at', to);

  const { data, error } = await query;
  if (error) throw new Error('disbursement_report query failed');

  return ((data ?? []) as unknown as Array<Record<string, any>>).map((r) => {
    const loan = embedAsObject<{ loan_number?: string; lender_profiles?: any }>(r.loan as any);
    const lender = loan ? embedAsObject<{ users?: { first_name?: string; last_name?: string } }>(loan.lender_profiles as any) : null;
    const lenderUser = lender ? embedAsObject(lender.users) : null;
    const authorizedBy = embedAsObject<{ first_name?: string; last_name?: string }>(r.authorized_by_user);
    return {
      loanNumber: loan?.loan_number ?? '—',
      lenderName: name(lenderUser?.first_name, lenderUser?.last_name),
      method: r.method,
      amount: r.amount,
      status: r.status,
      authorizedBy: name(authorizedBy?.first_name, authorizedBy?.last_name),
      createdAt: r.created_at,
      disbursedAt: r.disbursed_at,
    };
  });
}

async function fetchReportData(
  db: Db,
  templateKey: string,
  params: Record<string, string>,
): Promise<unknown[]> {
  switch (templateKey) {
    case 'loan_summary':
      return buildLoanSummary(db, params);
    case 'payment_report':
      return buildPaymentReport(db, params);
    case 'collection_report':
      return buildCollectionReport(db, params);
    case 'lender_report':
      return buildLenderReport(db, params, false);
    case 'account_upgrade_report':
      return buildLenderReport(db, params, true);
    case 'rider_report':
      return buildRiderReport(db, params);
    case 'employee_report':
      return buildEmployeeReport(db, params);
    case 'overdue_report':
      return buildOverdueReport(db);
    case 'financial_report':
      return buildFinancialRows(db, params, false, false);
    case 'revenue_report':
      return buildFinancialRows(db, params, false, false);
    case 'penalty_report':
      return buildFinancialRows(db, params, true, false);
    case 'interest_report':
      return buildFinancialRows(db, params, false, true);
    case 'audit_report':
      return buildAuditReport(db, params);
    case 'ci_report':
      return buildCiReport(db, params);
    case 'disbursement_report':
      return buildDisbursementReport(db, params);
    default:
      throw new Error('Unsupported report template');
  }
}

const SUPPORTED_TEMPLATES = new Set([
  'loan_summary', 'payment_report', 'collection_report', 'lender_report',
  'rider_report', 'employee_report', 'financial_report', 'revenue_report',
  'interest_report', 'penalty_report', 'overdue_report', 'audit_report',
  'ci_report', 'disbursement_report', 'account_upgrade_report',
]);

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER);
    if (roleCheck) return roleCheck;

    const body = await req.json();
    const { template_key, parameters } = body;

    if (!template_key || !SUPPORTED_TEMPLATES.has(template_key)) {
      return errorResponse('Unsupported report template', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();

    const { data: template } = await db
      .from('report_templates')
      .select('id, template_key, title')
      .eq('template_key', template_key)
      .eq('is_active', true)
      .maybeSingle();
    if (!template) return errorResponse('Report template is not active', 404, 'NOT_FOUND');

    const reportData = await fetchReportData(
      db,
      template_key,
      (parameters ?? {}) as Record<string, string>,
    );

    const { data: report, error: reportErr } = await db
      .from('reports')
      .insert({
        report_type: template_key,
        title: template.title,
        parameters: parameters ?? {},
        generated_by: authResult.id,
        data: reportData,
      })
      .select('id, title')
      .single();

    if (reportErr) return errorResponse('Failed to save report', 500, 'DB_ERROR');

    await writeAuditLog({
      performedBy: authResult.id,
      action: 'report_export',
      tableName: 'reports',
      recordId: report.id,
      newValues: { template_key, parameters },
    });

    return jsonResponse({
      success: true,
      report_id: report.id,
      template_name: template.title,
      row_count: reportData.length,
      data: reportData,
    });
  } catch (err) {
    console.error('reports-generate error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
