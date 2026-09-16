// supabase/functions/_shared/loan_financials.ts
// Single-source-of-truth helpers for the derived financial fields that were
// removed from the base tables in the 3NF normalization (00021):
//   - loans.total_payable / loans.outstanding_balance
//   - loan_schedules.amount_paid / status / paid_at
// All of these are now computed from loans + penalty_logs + payments.

import type { DbClient } from './types.ts';

export interface LoanFinancials {
  total_payable: number;
  interest_amount: number;
  penalties_total: number;
  payments_total: number;
  outstanding_balance: number;
}

export interface DisbursementRow {
  loan_id?: string;
  method: string | null;
  disbursed_at: string | null;
  xendit_id?: string | null;
  xendit_reference?: string | null;
  status?: string | null;
}

export interface LenderAddress {
  user_id: string;
  street: string | null;
  barangay: string | null;
  city: string | null;
  province: string | null;
  zip_code: string | null;
}

export interface DisbursementPref {
  loan_id: string;
  method: string | null;
  account: string | null;
}

export interface SchedulePaymentInfo {
  amount_paid: number;
  paid_at: string | null;
}

export interface PaymentRef {
  loan_schedule_id?: string | null;
  collection_assignment_id?: string | null;
}

interface PenaltyRow {
  penalty_amount: string | number;
}

interface PaymentRow {
  id?: string;
  amount: string | number;
  paid_at?: string | null;
  loan_schedule_id?: string | null;
  collection_assignment_id?: string | null;
}

interface ScheduleRow {
  id: string;
  loan_id?: string;
}

export const round2 = (n: number): number => Math.round(n * 100) / 100;

export const DEFAULT_INTEREST_RATE = 0.20;

export function computeTotalPayable(principal: number, interestRatePct: number): number {
  return round2(principal * (1 + interestRatePct / 100));
}

export function computeInterestAmount(principal: number, totalPayable: number): number {
  return Math.max(0, round2(totalPayable - principal));
}

// Sum ng VERIFIED payments kada loan, mula sa LAHAT ng link na konektado sa
// loan — hindi lang sa `loan_schedule_id`.
//
// MAHALAGA: ang isang rider-collection payment ay konektado sa loan sa
// pamamagitan ng (a) `loan_schedule_id` (allocation) AT (b)
// `collection_assignment_id` (ang koleksyon na nag-record nito). Dati, (a)
// lang ang binibilang ng balance. Kapag nawala o hindi tumutugma ang (a) —
// hal. muling nabuo ang `loan_schedules` (backfill), o naka-NULL ang
// `loan_schedule_id` ng payment — HINDI nababawas ang outstanding balance
// kahit na-record ang bayad at naging `completed` ang koleksyon (ang record
// at upload-proof ay kumikilala ng payment sa pamamagitan ng (b), kaya
// "completed pero hindi nabawasan" ang eksaktong sintomas).
//
// Ang (b) ay fallback lamang, at deduplicated sa pamamagitan ng payment id —
// hindi maaaring mabilang nang doble ang isang bayad.
// Mga collection na HINDI pa dapat binibilang sa loan balance: ang rider ay
// naka-record na ng `verified` payment, pero hindi pa ito ina-approve ng Head
// Manager/Employee. Sa `completed` lang (approved) siya nagiging epektibo.
export const NON_COUNTING_COLLECTION_STATUSES = ['pending_approval', 'rejected'] as const;

export async function sumVerifiedPaymentsByLoan(
  db: DbClient,
  scheduleRows: ScheduleRow[],
): Promise<Record<string, number>> {
  const paidByLoan: Record<string, number> = {};
  const scheduleLoan = new Map<string, string>(
    (scheduleRows ?? [])
      .filter((s) => s?.id && s?.loan_id)
      .map((s) => [String(s.id), String(s.loan_id)]),
  );
  const scheduleIds = [...scheduleLoan.keys()];
  if (scheduleIds.length === 0) return paidByLoan;

  // (a) payment → loan_schedule (normal na allocation).
  const { data: bySchedule } = await db
    .from('payments')
    .select('id, amount, loan_schedule_id, collection_assignment_id')
    .eq('status', 'verified')
    .in('loan_schedule_id', scheduleIds);

  // (b) payment → collection_assignment → loan_schedule (fallback/repair).
  const { data: assignmentRows } = await db
    .from('collection_assignments')
    .select('id, loan_schedule_id, status')
    .in('loan_schedule_id', scheduleIds);
  const assignmentLoan = new Map<string, string>();
  // Mga koleksyong naghihintay pa ng approval (o rejected) — ang verified na
  // bayad nila ay HINDI pa binibilang sa balance hanggang ma-approve.
  const nonCounting = new Set<string>();
  for (const a of (assignmentRows ?? []) as Array<{ id: string; loan_schedule_id: string | null; status: string | null }>) {
    const lid = scheduleLoan.get(String(a.loan_schedule_id));
    if (lid) assignmentLoan.set(String(a.id), lid);
    if ((NON_COUNTING_COLLECTION_STATUSES as readonly string[]).includes(String(a.status))) {
      nonCounting.add(String(a.id));
    }
  }
  let byAssignment: PaymentRow[] = [];
  const assignmentIds = [...assignmentLoan.keys()].filter((id) => !nonCounting.has(id));
  if (assignmentIds.length > 0) {
    const { data } = await db
      .from('payments')
      .select('id, amount, collection_assignment_id')
      .eq('status', 'verified')
      .in('collection_assignment_id', assignmentIds);
    byAssignment = (data ?? []) as PaymentRow[];
  }

  const counted = new Set<string>();
  for (const p of (bySchedule ?? []) as PaymentRow[]) {
    // Bayad na naka-link sa koleksyong hindi pa approved — huwag bilangin.
    if (p.collection_assignment_id && nonCounting.has(String(p.collection_assignment_id))) continue;
    const lid = scheduleLoan.get(String(p.loan_schedule_id));
    if (!lid) continue;
    if (p.id) counted.add(String(p.id));
    paidByLoan[lid] = round2((paidByLoan[lid] ?? 0) + Number(p.amount));
  }
  for (const p of byAssignment) {
    if (p.id && counted.has(String(p.id))) continue; // hindi ma-doble
    const lid = assignmentLoan.get(String(p.collection_assignment_id));
    if (!lid) continue;
    paidByLoan[lid] = round2((paidByLoan[lid] ?? 0) + Number(p.amount));
  }
  return paidByLoan;
}

// Outstanding balance = total_payable + penalties - verified payments.
// `db` is the service-role client returned by getAdminClient().
export async function getLoanFinancials(db: DbClient, loanId: string): Promise<LoanFinancials | null> {
  const { data: loan } = await db
    .from('loans')
    .select('principal_amount, interest_rate')
    .eq('id', loanId)
    .single();
  if (!loan) return null;

  const totalPayable = computeTotalPayable(Number(loan.principal_amount), Number(loan.interest_rate));

  const { data: penaltyRows } = await db
    .from('penalty_logs')
    .select('penalty_amount')
    .eq('loan_id', loanId);
  const penaltiesTotal = round2((penaltyRows ?? []).reduce((s: number, p: PenaltyRow) => s + Number(p.penalty_amount), 0));

  const { data: scheduleRows } = await db
    .from('loan_schedules')
    .select('id, loan_id')
    .eq('loan_id', loanId);
  const paidByLoan = await sumVerifiedPaymentsByLoan(db, (scheduleRows ?? []) as ScheduleRow[]);
  const paymentsTotal = round2(paidByLoan[loanId] ?? 0);

  const outstandingBalance = Math.max(0, round2(totalPayable + penaltiesTotal - paymentsTotal));

  return {
    total_payable: totalPayable,
    interest_amount: computeInterestAmount(Number(loan.principal_amount), totalPayable),
    penalties_total: penaltiesTotal,
    payments_total: paymentsTotal,
    outstanding_balance: outstandingBalance,
  };
}

// Amount paid against a single schedule from its verified payments.
export async function getSchedulePayment(db: DbClient, scheduleId: string): Promise<SchedulePaymentInfo> {
  const { data: rows } = await db
    .from('payments')
    .select('amount, paid_at, collection_assignment_id')
    .eq('loan_schedule_id', scheduleId)
    .eq('status', 'verified');

  // Huwag bilangin ang bayad ng koleksyong hindi pa approved ng HM/Employee.
  const assignmentIds = [...new Set((rows ?? [])
    .map((r) => (r as PaymentRow).collection_assignment_id)
    .filter((v): v is string => !!v))];
  const nonCounting = new Set<string>();
  if (assignmentIds.length > 0) {
    const { data: cas } = await db
      .from('collection_assignments')
      .select('id, status')
      .in('id', assignmentIds);
    for (const a of (cas ?? []) as Array<{ id: string; status: string | null }>) {
      if ((NON_COUNTING_COLLECTION_STATUSES as readonly string[]).includes(String(a.status))) {
        nonCounting.add(String(a.id));
      }
    }
  }

  let amountPaid = 0;
  let paidAt: string | null = null;
  for (const p of rows ?? []) {
    const row = p as PaymentRow;
    if (row.collection_assignment_id && nonCounting.has(String(row.collection_assignment_id))) continue;
    amountPaid = round2(amountPaid + Number(p.amount));
    if (p.paid_at && (!paidAt || p.paid_at > paidAt)) paidAt = p.paid_at;
  }
  return { amount_paid: amountPaid, paid_at: paidAt };
}

// Allocate a payment across a loan's unpaid schedules in installment order
// (oldest first): each schedule is filled up to its remaining due, then the
// excess rolls forward to later installments. This is what makes advance
// payments land on the right installments instead of overpaying one schedule.
// The caller must already cap `amount` at the loan's outstanding balance.
export interface AllocatedPayment {
  loan_schedule_id: string;
  amount: number;
}

/**
 * Nag-aallocate ng bayad sa mga unpaid na installment.
 *
 * Default: oldest installment first (waterfall) — ito ang tama para sa
 * koleksyon at sa mga bayad na walang partikular na installment.
 *
 * Kapag may `preferScheduleId` (hal. ang row na pinindot ng staff sa Payment
 * Schedule), iyon ang UNAHANG babayaran — kung hindi, mapupunta ang bayad sa
 * PINAKA-LUMANG unpaid na installment at mananatiling `pending` ang
 * installment na talagang binabayaran kahit naka-record na ang pera.
 *
 * Ang natitirang halaga ay tuloy-tuloy sa pinaka-lumang unpaid pa
 * (oldest-first waterfall) — kaya hindi mananatiling overdue ang lumang
 * installment habang may bayad na ang mas bago. Kapag bayad na ang mga luma
 * (normal na kaso), ang sobra ay natural na umaabot sa mga susunod pang
 * installment (advance payment).
 */
export async function allocatePayment(
  db: DbClient,
  loanId: string,
  amount: number,
  preferScheduleId?: string,
): Promise<AllocatedPayment[]> {
  const { data: schedules } = await db
    .from('v_loan_schedules')
    .select('id, amount_due, amount_paid')
    .eq('loan_id', loanId)
    .order('installment_number', { ascending: true });

  const all = schedules ?? [];
  // Ang pinindot na installment ay nauuna; ang natitira ay mananatili sa
  // installment-number order (oldest first).
  const ordered = preferScheduleId
    ? [
        ...all.filter((s) => s.id === preferScheduleId),
        ...all.filter((s) => s.id !== preferScheduleId),
      ]
    : all;

  const allocations: AllocatedPayment[] = [];
  let left = round2(amount);
  for (const s of ordered) {
    if (left <= 0) break;
    const remaining = round2(Number(s.amount_due) - Number(s.amount_paid ?? 0));
    if (remaining <= 0) continue;
    const applied = Math.min(remaining, left);
    allocations.push({ loan_schedule_id: s.id, amount: applied });
    left = round2(left - applied);
  }
  if (left > 0 && allocations.length > 0) {
    // Caller caps at outstanding balance, so this is centavos-level rounding
    // dust — fold it into the last allocation rather than losing it.
    const last = allocations[allocations.length - 1];
    last.amount = round2(last.amount + left);
  } else if (left > 0 && ordered.length > 0) {
    // Defensive fallback (everything unexpectedly paid): keep the money on the
    // last schedule instead of silently dropping it.
    const lastSchedule = ordered[ordered.length - 1];
    allocations.push({ loan_schedule_id: lastSchedule.id, amount: left });
  }
  return allocations;
}

export function scheduleStatus(amountPaid: number, amountDue: number, dueDate?: string): string {
  if (amountPaid >= amountDue) return 'paid';
  if (amountPaid > 0) return 'partial';
  if (dueDate) {
    const due = new Date(`${dueDate}T00:00:00`);
    const today = new Date();
    const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    if (due.getTime() < todayStart.getTime()) return 'overdue';
  }
  return 'pending';
}

// Resolve the loan_id for a payment row now that payments.loan_id is gone.
export async function getPaymentLoanId(db: DbClient, payment: PaymentRef): Promise<string | null> {
  if (payment.loan_schedule_id) {
    const { data } = await db.from('loan_schedules').select('loan_id').eq('id', payment.loan_schedule_id).single();
    return data?.loan_id ?? null;
  }
  if (payment.collection_assignment_id) {
    const { data: ca } = await db
      .from('collection_assignments')
      .select('loan_schedule_id')
      .eq('id', payment.collection_assignment_id)
      .single();
    if (ca?.loan_schedule_id) {
      const { data } = await db.from('loan_schedules').select('loan_id').eq('id', ca.loan_schedule_id).single();
      return data?.loan_id ?? null;
    }
  }
  return null;
}

// Latest disbursement for a loan (loans no longer carries disbursement snapshots).
export async function getLoanDisbursement(db: DbClient, loanId: string): Promise<DisbursementRow | null> {
  const { data } = await db
    .from('disbursements')
    .select('method, disbursed_at, xendit_id, xendit_reference, status')
    .eq('loan_id', loanId)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  return data ?? null;
}

export async function hasPenaltyApplied(db: DbClient, loanId: string): Promise<boolean> {
  const { count } = await db
    .from('penalty_logs')
    .select('*', { count: 'exact', head: true })
    .eq('loan_id', loanId);
  return (count ?? 0) > 0;
}

// Primary (home) address for a user (lender_profiles no longer carries it).
export async function getLenderAddress(db: DbClient, userId: string): Promise<LenderAddress | null> {
  const { data } = await db
    .from('addresses')
    .select('street, barangay, city, province, zip_code')
    .eq('user_id', userId)
    .eq('is_primary', true)
    .maybeSingle();
  return (data ?? null) as LenderAddress | null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Batch variants for list endpoints (avoids N+1 round-trips).
// ─────────────────────────────────────────────────────────────────────────────

export async function getLoanFinancialsBatch(db: DbClient, loanIds: string[]): Promise<Record<string, LoanFinancials>> {
  const ids = (loanIds ?? []).filter(Boolean);
  const map: Record<string, LoanFinancials> = {};
  if (ids.length === 0) return map;

  // Fire first 3 queries in parallel (no dependencies)
  const [
    { data: loanRows },
    { data: penaltyRows },
    { data: scheduleRows },
  ] = await Promise.all([
    db.from('loans').select('id, principal_amount, interest_rate').in('id', ids),
    db.from('penalty_logs').select('loan_id, penalty_amount').in('loan_id', ids),
    db.from('loan_schedules').select('id, loan_id').in('loan_id', ids),
  ]);

  const paidByLoan = await sumVerifiedPaymentsByLoan(db, (scheduleRows ?? []) as ScheduleRow[]);
  const penaltyByLoan: Record<string, number> = {};
  for (const p of penaltyRows ?? []) {
    penaltyByLoan[p.loan_id] = round2((penaltyByLoan[p.loan_id] ?? 0) + Number(p.penalty_amount));
  }

  for (const l of loanRows ?? []) {
    const totalPayable = computeTotalPayable(Number(l.principal_amount), Number(l.interest_rate));
    const outstandingBalance = Math.max(0, round2(
      totalPayable + (penaltyByLoan[l.id] ?? 0) - (paidByLoan[l.id] ?? 0),
    ));
    map[l.id] = {
      total_payable: totalPayable,
      interest_amount: computeInterestAmount(Number(l.principal_amount), totalPayable),
      penalties_total: penaltyByLoan[l.id] ?? 0,
      payments_total: paidByLoan[l.id] ?? 0,
      outstanding_balance: outstandingBalance,
    };
  }
  return map;
}

// Latest disbursement per loan.
export async function getLoanDisbursementsBatch(db: DbClient, loanIds: string[]): Promise<Record<string, DisbursementRow>> {
  const ids = (loanIds ?? []).filter(Boolean);
  const map: Record<string, DisbursementRow> = {};
  if (ids.length === 0) return map;
  const { data } = await db
    .from('disbursements')
    .select('loan_id, method, disbursed_at')
    .in('loan_id', ids)
    .order('created_at', { ascending: false });
  for (const d of data ?? []) {
    if (!map[d.loan_id]) map[d.loan_id] = d;
  }
  return map;
}

// Primary (home) address per user.
export async function getLenderAddressBatch(db: DbClient, userIds: string[]): Promise<Record<string, LenderAddress>> {
  const ids = (userIds ?? []).filter(Boolean);
  const map: Record<string, LenderAddress> = {};
  if (ids.length === 0) return map;
  const { data } = await db
    .from('addresses')
    .select('user_id, street, barangay, city, province, zip_code')
    .eq('is_primary', true)
    .in('user_id', ids);
  for (const a of data ?? []) map[a.user_id] = a;
  return map;
}

// Disbursement preference per loan (1:1 with loans; separate from the
// disbursements event table so the base loan row stays free of snapshots).
export async function getLoanDisbursementPrefsBatch(db: DbClient, loanIds: string[]): Promise<Record<string, DisbursementPref>> {
  const ids = (loanIds ?? []).filter(Boolean);
  const map: Record<string, DisbursementPref> = {};
  if (ids.length === 0) return map;
  const { data } = await db
    .from('loan_disbursement_preferences')
    .select('loan_id, method, account')
    .in('loan_id', ids);
  for (const p of data ?? []) map[p.loan_id] = p;
  return map;
}
