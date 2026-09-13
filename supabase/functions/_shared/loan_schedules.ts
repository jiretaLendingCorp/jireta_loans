// supabase/functions/_shared/loan_schedules.ts
// ─────────────────────────────────────────────────────────────────────────────
// BUSINESS RULE: ang PANAHON NG PAGBAYAD (due dates ng installment) ay
// nagsisimula kapag ACTIVE na ang loan — i.e. pagkatapos ma-release /
// ma-disburse, hindi sa oras ng application.
//
// Paano ito ipinatutupad nang LIGTAS:
//   • Ang `loan_schedules` rows ay ginagawa pa rin sa oras ng application
//     (loans-apply / kyc-view / in-office-view) — kaya HINDI umaasa sa deploy
//     order ang anumang payment: laging may a-allocate-an ang bayad.
//   • Sa oras ng ACTIVATION (gcash / office cash / rider delivery / xendit
//     webhook), ang due dates ay IN-REBASE (binabago ang `due_date`) simula sa
//     petsa ng release. Ito ang "day 0" ng mga installment.
//   • Ang mga pre-activation rows ay HINDI ipinapakita: ang `loans-view` ay
//     hindi nagbabalik ng `loan_schedules`/`due_date` hangga't hindi
//     active/overdue/completed ang loan.
//
// Bakit in-place (update) at hindi delete+insert ang rebase:
//   • Ang `collection_assignments.loan_schedule_id` at `payments` ay maaaring
//     naka-reference na sa mga schedule row; ang pag-delete ay puwedeng
//     mabigo (FK) o makasira ng reference.
//   • Idempotent din ito — puwedeng tawagin muli (hal. webhook na naulit)
//     nang walang epekto sa mga bayad.
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

interface ScheduleRowLite {
  id: string;
  installment_number: number | null;
  due_date: string | null;
}

const PAYABLE_STATUSES = ['active', 'overdue', 'completed'];

/** Statuses kung saan dapat may visible/aktibong payment schedule ang loan. */
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

function planFor(loan: LoanScheduleSource, startDate: Date): ReturnType<typeof computeSchedule> {
  const frequency = String(loan.payment_frequency ?? 'monthly').toLowerCase();
  return computeSchedule(
    Number(loan.principal_amount),
    frequency,
    startDate,
    loan.term_periods ?? undefined,
  );
}

async function scheduleRowsOf(db: DbClient, loanId: string): Promise<ScheduleRowLite[]> {
  const { data } = await db
    .from('loan_schedules')
    .select('id, installment_number, due_date')
    .eq('loan_id', loanId)
    .order('installment_number', { ascending: true });
  return (data ?? []) as ScheduleRowLite[];
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
  const sched = planFor(loan, startDate);
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
 * Gumagawa ng schedule KUNG WALA PA. Safety net para sa payment recording:
 * kahit na-miss ang activation hook, hindi dapat ma-stuck ang koleksyon sa
 * "No unpaid installments to apply the payment to".
 *
 * Returns true kapag may nagawang bagong schedule.
 */
export async function ensureLoanSchedulesIfMissing(
  db: DbClient,
  loanId: string,
  startDate: Date = new Date(),
): Promise<boolean> {
  const existing = await scheduleRowsOf(db, loanId);
  if (existing.length > 0) return false;
  const loan = await loadLoan(db, loanId);
  if (!loan) return false;
  await insertScheduleRows(db, loan, startDate);
  return true;
}

/**
 * Itinakda ang "day 0" ng payment period sa oras ng pag-activate ng loan.
 *
 * In-place ang pag-rebase ng `due_date` (update, hindi delete) — kaya:
 *   • hindi masisira ang `collection_assignments.loan_schedule_id` o `payments`
 *     na naka-link na sa schedule row,
 *   • idempotent — puwedeng tawagin muli nang walang epekto.
 *
 * Kung may VERIFIED payment nang naka-link, HINDI ito ginagalaw (partially
 * paid / legacy na loan).
 */
export async function startLoanPaymentSchedule(
  db: DbClient,
  loanId: string,
  startDate: Date = new Date(),
): Promise<void> {
  const loan = await loadLoan(db, loanId);
  if (!loan) return;

  const existing = await scheduleRowsOf(db, loanId);
  if (existing.length > 0 && (await hasVerifiedPayment(db, existing.map((r) => r.id)))) {
    return; // may bayad na — huwag galawin ang anuman
  }

  const sched = planFor(loan, startDate);

  // Normal na kaso: pareho ang bilang ng installment → i-rebase lang ang dates.
  if (existing.length === sched.installments) {
    let changed = 0;
    for (let i = 0; i < existing.length; i++) {
      const nextDue = sched.dueDates[i];
      if (!nextDue || existing[i].due_date === nextDue) continue;
      const { error } = await db
        .from('loan_schedules')
        .update({ due_date: nextDue })
        .eq('id', existing[i].id);
      if (error) {
        console.error('[loan_schedules] due-date rebase failed', {
          loanId,
          scheduleId: existing[i].id,
          error: error.message,
        });
      } else {
        changed++;
      }
    }
    console.log(
      `[loan_schedules] rebased ${changed}/${existing.length} due dates for loan ${loanId} starting ${sched.dueDates[0]}`,
    );
    return;
  }

  // Hindi tugma ang bilang (o wala pang rows) → gawin muli. Ligtas pa rin dahil
  // walang verified payment (nasuri sa itaas).
  if (existing.length > 0) {
    const { error: delErr } = await db
      .from('loan_schedules')
      .delete()
      .in('id', existing.map((r) => r.id));
    if (delErr) {
      console.error('[loan_schedules] delete failed', { loanId, error: delErr.message });
      return; // huwag mag-insert — iiwan ang doble
    }
  }
  await insertScheduleRows(db, loan, startDate);
}
