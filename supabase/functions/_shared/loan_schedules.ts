// supabase/functions/_shared/loan_schedules.ts
// ─────────────────────────────────────────────────────────────────────────────
// BUSINESS RULE: ang payment schedule (mga installment at due date) ay
// nagsisimula lang kapag ACTIVE na ang loan — i.e. pagkatapos ma-release /
// ma-disburse, hindi sa oras ng application.
//
// Dati, ang `loan_schedules` ay ginagawa na sa oras ng APPLICATION
// (loans-apply / kyc-view / in-office-view) gamit ang petsa ng application.
// Kaya:
//   • may "Payment Schedule" na nakikita sa Loan Application Details kahit
//     hindi pa aktivado ang loan, at
//   • kapag na-release naman (ilang araw pagkatapos), ang unang mga
//     installment ay overdue na agad dahil sa petsa ng application naka-base
//     ang due dates.
//
// Ngayon, isang lugar lang ang gumagawa ng schedule — sa pag-activate ng loan
// (gcash / office cash / rider delivery / xendit webhook) — at ang due dates ay
// naka-base sa petsa ng pag-release.
// ─────────────────────────────────────────────────────────────────────────────

import type { DbClient } from './types.ts';
import { computeSchedule } from './schedule.ts';

interface LoanScheduleSource {
  id: string;
  principal_amount: string | number;
  interest_rate?: string | number | null;
  payment_frequency?: string | null;
  term_periods?: number | null;
}

const PAYABLE_STATUSES = ['active', 'overdue', 'completed'];

/** Statuses kung saan dapat may payment schedule na ang loan. */
export function isReleasedLoanStatus(status: string | null | undefined): boolean {
  return PAYABLE_STATUSES.includes(String(status ?? '').toLowerCase());
}

async function loadLoan(db: DbClient, loanId: string): Promise<LoanScheduleSource | null> {
  const { data } = await db
    .from('loans')
    .select('id, principal_amount, interest_rate, payment_frequency, term_periods')
    .eq('id', loanId)
    .maybeSingle();
  return (data ?? null) as LoanScheduleSource | null;
}

async function scheduleIdsOf(db: DbClient, loanId: string): Promise<string[]> {
  const { data } = await db.from('loan_schedules').select('id').eq('loan_id', loanId);
  return ((data ?? []) as Array<{ id: string }>).map((r) => r.id);
}

async function hasVerifiedPayment(db: DbClient, scheduleIds: string[]): Promise<boolean> {
  if (scheduleIds.length === 0) return false;
  const { count } = await db
    .from('payments')
    .select('*', { count: 'exact', head: true })
    .in('loan_schedule_id', scheduleIds)
    .eq('status', 'verified');
  return (count ?? 0) > 0;
}

async function insertScheduleRows(
  db: DbClient,
  loan: LoanScheduleSource,
  startDate: Date,
): Promise<void> {
  const frequency = String(loan.payment_frequency ?? 'monthly').toLowerCase();
  const sched = computeSchedule(
    Number(loan.principal_amount),
    frequency,
    startDate,
    loan.term_periods ?? undefined,
  );
  const rows = sched.dueDates.map((date, i) => ({
    loan_id: loan.id,
    installment_number: i + 1,
    due_date: date,
    amount_due: sched.amounts[i],
  }));
  if (rows.length === 0) return;
  const { error } = await db.from('loan_schedules').insert(rows);
  if (error) {
    console.error('[loan_schedules] insert failed', { loanId: loan.id, error: error.message });
    return;
  }
  console.log(
    `[loan_schedules] generated ${rows.length} installments for loan ${loan.id} starting ${sched.dueDates[0]}`,
  );
}

/**
 * Gumagawa ng schedule KUNG WALA PA. Ginagamit bilang safety net sa payment
 * recording (kapag na-miss ang activation hook, dapat hindi ma-stuck ang
 * koleksyon sa "No unpaid installments").
 *
 * Returns true kapag may nagawang bagong schedule.
 */
export async function ensureLoanSchedulesIfMissing(
  db: DbClient,
  loanId: string,
  startDate: Date = new Date(),
): Promise<boolean> {
  const existing = await scheduleIdsOf(db, loanId);
  if (existing.length > 0) return false;
  const loan = await loadLoan(db, loanId);
  if (!loan) return false;
  await insertScheduleRows(db, loan, startDate);
  return true;
}

/**
 * Nagsisimula (o nagsisimula muli) ng payment schedule sa oras ng pag-activate
 * ng loan — ang `startDate` ang araw 0 ng mga installment.
 *
 * Idempotent at ligtas: kung may VERIFIED payment nang naka-link sa mga
 * schedule, HINDI ito ginagalaw (legacy/partially-paid na loan).
 */
export async function startLoanPaymentSchedule(
  db: DbClient,
  loanId: string,
  startDate: Date = new Date(),
): Promise<void> {
  const loan = await loadLoan(db, loanId);
  if (!loan) return;

  const existing = await scheduleIdsOf(db, loanId);
  if (existing.length > 0) {
    if (await hasVerifiedPayment(db, existing)) return; // may bayad na — huwag galawin
    const { error: delErr } = await db.from('loan_schedules').delete().in('id', existing);
    if (delErr) {
      console.error('[loan_schedules] delete failed', { loanId, error: delErr.message });
      return; // huwag mag-insert kung hindi natanggal — maiiwan ang doble
    }
  }
  await insertScheduleRows(db, loan, startDate);
}
