// supabase/functions/_shared/loan_financials.ts
// Single-source-of-truth helpers for the derived financial fields that were
// removed from the base tables in the 3NF normalization (00021):
//   - loans.total_payable / loans.outstanding_balance
//   - loan_schedules.amount_paid / status / paid_at
// All of these are now computed from loans + penalty_logs + payments.

export const round2 = (n: number): number => Math.round(n * 100) / 100;

export const DEFAULT_INTEREST_RATE = 0.20;

export function computeTotalPayable(principal: number, interestRatePct: number): number {
  return round2(principal * (1 + interestRatePct / 100));
}

export function computeInterestAmount(principal: number, totalPayable: number): number {
  return Math.max(0, round2(totalPayable - principal));
}

// Outstanding balance = total_payable + penalties - verified payments.
// `db` is the service-role client returned by getAdminClient().
export async function getLoanFinancials(db: any, loanId: string) {
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
  const penaltiesTotal = round2((penaltyRows ?? []).reduce((s: number, p: any) => s + Number(p.penalty_amount), 0));

  const { data: scheduleRows } = await db
    .from('loan_schedules')
    .select('id')
    .eq('loan_id', loanId);
  const scheduleIds = (scheduleRows ?? []).map((s: any) => s.id);

  let paymentsTotal = 0;
  if (scheduleIds.length > 0) {
    const { data: payRows } = await db
      .from('payments')
      .select('amount')
      .eq('status', 'verified')
      .in('loan_schedule_id', scheduleIds);
    paymentsTotal = round2((payRows ?? []).reduce((s: number, p: any) => s + Number(p.amount), 0));
  }

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
export async function getSchedulePayment(db: any, scheduleId: string) {
  const { data: rows } = await db
    .from('payments')
    .select('amount, paid_at')
    .eq('loan_schedule_id', scheduleId)
    .eq('status', 'verified');

  let amountPaid = 0;
  let paidAt: string | null = null;
  for (const p of rows ?? []) {
    amountPaid = round2(amountPaid + Number(p.amount));
    if (p.paid_at && (!paidAt || p.paid_at > paidAt)) paidAt = p.paid_at;
  }
  return { amount_paid: amountPaid, paid_at: paidAt };
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
export async function getPaymentLoanId(db: any, payment: any): Promise<string | null> {
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
export async function getLoanDisbursement(db: any, loanId: string) {
  const { data } = await db
    .from('disbursements')
    .select('method, disbursed_at, xendit_id, xendit_reference, status')
    .eq('loan_id', loanId)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  return data ?? null;
}

export async function hasPenaltyApplied(db: any, loanId: string): Promise<boolean> {
  const { count } = await db
    .from('penalty_logs')
    .select('*', { count: 'exact', head: true })
    .eq('loan_id', loanId);
  return (count ?? 0) > 0;
}

// Active blacklist entry for a lender (lender_profiles no longer carries it).
export async function getLenderBlacklist(db: any, lenderId: string) {
  const { data } = await db
    .from('blacklist')
    .select('reason, added_by, added_at, removed_by, removed_at, is_active')
    .eq('lender_id', lenderId)
    .eq('is_active', true)
    .maybeSingle();
  return data ?? null;
}

// Primary (home) address for a user (lender_profiles no longer carries it).
export async function getLenderAddress(db: any, userId: string) {
  const { data } = await db
    .from('addresses')
    .select('street, barangay, city, province, zip_code')
    .eq('user_id', userId)
    .eq('is_primary', true)
    .maybeSingle();
  return data ?? null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Batch variants for list endpoints (avoids N+1 round-trips).
// ─────────────────────────────────────────────────────────────────────────────

export async function getLoanFinancialsBatch(db: any, loanIds: string[]) {
  const ids = (loanIds ?? []).filter(Boolean);
  const map: Record<string, any> = {};
  if (ids.length === 0) return map;

  const { data: loanRows } = await db
    .from('loans')
    .select('id, principal_amount, interest_rate')
    .in('id', ids);

  const { data: penaltyRows } = await db
    .from('penalty_logs')
    .select('loan_id, penalty_amount')
    .in('loan_id', ids);

  const { data: scheduleRows } = await db
    .from('loan_schedules')
    .select('id, loan_id')
    .in('loan_id', ids);

  const scheduleIds = (scheduleRows ?? []).map((s: any) => s.id);
  let payRows: any[] = [];
  if (scheduleIds.length > 0) {
    const { data } = await db
      .from('payments')
      .select('amount, loan_schedule_id')
      .eq('status', 'verified')
      .in('loan_schedule_id', scheduleIds);
    payRows = data ?? [];
  }

  const scheduleLoan = new Map((scheduleRows ?? []).map((s: any) => [s.id, s.loan_id]));
  const paidByLoan: Record<string, number> = {};
  for (const p of payRows) {
    const lid = scheduleLoan.get(p.loan_schedule_id);
    if (lid) paidByLoan[lid] = round2((paidByLoan[lid] ?? 0) + Number(p.amount));
  }
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
export async function getLoanDisbursementsBatch(db: any, loanIds: string[]) {
  const ids = (loanIds ?? []).filter(Boolean);
  const map: Record<string, any> = {};
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

// Active blacklist per lender.
export async function getLenderBlacklistBatch(db: any, lenderIds: string[]) {
  const ids = (lenderIds ?? []).filter(Boolean);
  const map: Record<string, any> = {};
  if (ids.length === 0) return map;
  const { data } = await db
    .from('blacklist')
    .select('lender_id')
    .eq('is_active', true)
    .in('lender_id', ids);
  for (const b of data ?? []) map[b.lender_id] = b;
  return map;
}

// Primary (home) address per user.
export async function getLenderAddressBatch(db: any, userIds: string[]) {
  const ids = (userIds ?? []).filter(Boolean);
  const map: Record<string, any> = {};
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
export async function getLoanDisbursementPrefsBatch(db: any, loanIds: string[]) {
  const ids = (loanIds ?? []).filter(Boolean);
  const map: Record<string, any> = {};
  if (ids.length === 0) return map;
  const { data } = await db
    .from('loan_disbursement_preferences')
    .select('loan_id, method, account')
    .in('loan_id', ids);
  for (const p of data ?? []) map[p.loan_id] = p;
  return map;
}
