// supabase/functions/_shared/schedule.ts
// Canonical loan schedule computation for Jireta LMS.
// Single source of truth — imported by loans-apply and loans-view so every
// endpoint (preview, apply, details) always produces identical schedules.
//
// Borrowing rules (enforced here and in validators.ts):
//   - Principal range  : ₱3,000 (min) – ₱500,000 (max)
//   - Interest rate    : flat 20% of the principal (₱3,000 → ₱3,600 payable)
//   - Term by amount   : ≤5,000 → 40d · ≤10,000 → 60d · ≤20,000 → 70d
//                        ≤50,000 → 80d · ≤100,000 → 120d · else → 180d
//   - Per-period rates : daily = total / termDays
//                        weekly = daily × 7
//                        monthly = total / ceil(termDays / 30)
//   - Every period is fully itemised (amount, principal, interest, balance);
//     the final installment absorbs any rounding remainder so the payments
//     always sum back to the exact total payable.

export const INTEREST_RATE = 0.20; // 20% flat — server-side enforced
export const MIN_LOAN_AMOUNT = 3_000;
export const MAX_LOAN_AMOUNT = 500_000;

export const round2 = (n: number): number => Math.round(n * 100) / 100;

export type PaymentFrequency = 'daily' | 'weekly' | 'monthly';

export interface SchedulePeriod {
  period: number;
  due_date: string;
  amount: number;
  principal: number;
  interest: number;
  balance: number;
}

export interface ScheduleResult {
  principal: number;
  interest: number;
  totalPayable: number;
  termDays: number;
  frequency: PaymentFrequency;
  installmentAmount: number;
  installments: number;
  maxPeriods: number;
  dueDates: string[];
  amounts: number[];
  periods: SchedulePeriod[];
}

export function termDaysFor(principal: number): number {
  if (principal <= 5_000) return 40;
  if (principal <= 10_000) return 60;
  if (principal <= 20_000) return 70;
  if (principal <= 50_000) return 80;
  if (principal <= 100_000) return 120;
  return 180;
}

function toDateStr(d: Date): string {
  return d.toISOString().split('T')[0];
}

export function isValidFrequency(freq: string): freq is PaymentFrequency {
  return freq === 'daily' || freq === 'weekly' || freq === 'monthly';
}

export function maxPeriodsFor(frequency: string, termDays: number): number {
  if (frequency === 'daily') return termDays;
  if (frequency === 'weekly') return Math.max(1, Math.ceil(termDays / 7));
  return Math.max(1, Math.ceil(termDays / 30));
}

function intervalDaysFor(frequency: string): number {
  if (frequency === 'daily') return 1;
  if (frequency === 'weekly') return 7;
  return 30;
}

/**
 * Compute a fully itemised loan repayment schedule.
 *
 * @param principal  Loan principal in PHP (₱3,000 – ₱500,000)
 * @param frequency  'daily' | 'weekly' | 'monthly'
 * @param startDate  Date from which due dates are calculated (defaults to today)
 * @param periodsOverride  Optional lender-chosen number of periods (installments).
 *   For DAILY this is the number of days, WEEKLY the number of weeks, MONTHLY
 *   the number of months. Must be an integer within [1, maxPeriodsFor].
 *   The total payable (principal + 20% interest) is FIXED regardless of the
 *   chosen number of periods — selecting fewer periods just makes each payment
 *   larger. When omitted, the maximum number of periods within the deadline is
 *   used (i.e. the default per-period rate).
 */
export function computeSchedule(
  principal: number,
  frequency: string,
  startDate: Date = new Date(),
  periodsOverride?: number,
): ScheduleResult {
  const interest = round2(principal * INTEREST_RATE);
  const totalPayable = round2(principal + interest);
  const termDays = termDaysFor(principal);
  const intervalDays = intervalDaysFor(frequency);

  const maxPeriods = maxPeriodsFor(frequency, termDays);
  const hasOverride =
    typeof periodsOverride === 'number' &&
    Number.isInteger(periodsOverride) &&
    periodsOverride >= 1 &&
    periodsOverride <= maxPeriods;

  // Default behavior: use the maximum periods within the deadline.
  const installments = hasOverride ? periodsOverride! : maxPeriods;
  const baseInstallment = round2(totalPayable / installments);

  const dueDates: string[] = [];
  const amounts: number[] = [];
  for (let i = 0; i < installments; i++) {
    const due = new Date(startDate);
    due.setDate(due.getDate() + (i + 1) * intervalDays);
    dueDates.push(toDateStr(due));
    amounts.push(
      i === installments - 1
        ? round2(totalPayable - baseInstallment * (installments - 1))
        : baseInstallment,
    );
  }

  // Itemise every period: proportional principal/interest split + running balance.
  const principalRatio = principal / totalPayable;
  let cumulative = 0;
  const periods: SchedulePeriod[] = amounts.map((amount, i) => {
    const principalPart = round2(amount * principalRatio);
    const interestPart = round2(amount - principalPart);
    cumulative = round2(cumulative + amount);
    return {
      period: i + 1,
      due_date: dueDates[i],
      amount,
      principal: principalPart,
      interest: interestPart,
      balance: round2(Math.max(0, totalPayable - cumulative)),
    };
  });

  return {
    principal: round2(principal),
    interest,
    totalPayable,
    termDays,
    frequency: frequency as PaymentFrequency,
    installmentAmount: baseInstallment,
    installments,
    maxPeriods,
    dueDates,
    amounts,
    periods,
  };
}

export function generateLoanNumber(): string {
  const year = new Date().getFullYear();
  const rand = String(Math.floor(Math.random() * 1_000_000)).padStart(6, '0');
  return `LN-${year}-${rand}`;
}
