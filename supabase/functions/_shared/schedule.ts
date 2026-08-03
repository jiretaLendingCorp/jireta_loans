// supabase/functions/_shared/schedule.ts
// Canonical loan schedule computation for Jireta LMS.
// Single source of truth — imported by loans-apply and in-office-submit
// so both paths always produce identical schedules.

export const INTEREST_RATE = 0.20; // 20% flat — server-side enforced

export interface ScheduleResult {
  totalPayable: number;
  interest: number;
  termDays: number;
  installmentAmount: number;
  installments: number;
  dueDates: string[];
  amounts: number[];
}

/**
 * Compute a loan repayment schedule.
 *
 * @param principal  Loan principal in PHP (3,000 – 500,000)
 * @param frequency  'daily' | 'weekly' | 'monthly'
 * @param startDate  Date from which due dates are calculated (defaults to today)
 */
export function computeSchedule(
  principal: number,
  frequency: string,
  startDate: Date = new Date(),
): ScheduleResult {
  const interest = Math.round(principal * INTEREST_RATE * 100) / 100;
  const totalPayable = principal + interest;

  // Authoritative term brackets — matches system_config seed data
  let termDays: number;
  if (principal <= 5_000)       termDays = 40;
  else if (principal <= 10_000) termDays = 60;
  else if (principal <= 20_000) termDays = 70;
  else if (principal <= 50_000) termDays = 80;
  else if (principal <= 100_000) termDays = 120;
  else                           termDays = 180;

  let intervalDays: number;
  let installments: number;

  if (frequency === 'daily') {
    intervalDays = 1;
    installments = termDays;
  } else if (frequency === 'weekly') {
    intervalDays = 7;
    installments = Math.ceil(termDays / 7);
  } else {
    intervalDays = 30;
    installments = Math.ceil(termDays / 30);
  }

  // Floor all installments; absorb rounding remainder into the last one
  const baseInstallment =
    Math.floor((totalPayable / installments) * 100) / 100;
  const lastInstallment =
    Math.round(
      (totalPayable - baseInstallment * (installments - 1)) * 100,
    ) / 100;

  const dueDates: string[] = [];
  const amounts: number[] = [];

  for (let i = 0; i < installments; i++) {
    const due = new Date(startDate);
    due.setDate(due.getDate() + (i + 1) * intervalDays);
    dueDates.push(due.toISOString().split('T')[0]);
    amounts.push(i === installments - 1 ? lastInstallment : baseInstallment);
  }

  return {
    totalPayable,
    interest,
    termDays,
    installmentAmount: baseInstallment,
    installments,
    dueDates,
    amounts,
  };
}

export function generateLoanNumber(): string {
  const year = new Date().getFullYear();
  const rand = String(Math.floor(Math.random() * 1_000_000)).padStart(6, '0');
  return `LN-${year}-${rand}`;
}
