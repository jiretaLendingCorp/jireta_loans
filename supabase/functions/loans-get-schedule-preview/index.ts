// supabase/functions/loans-get-schedule-preview/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { validateLoanAmount, validateFrequency } from '../_shared/validators.ts';

const INTEREST_RATE = 0.20;

function computeSchedulePreview(principal: number, frequency: string) {
  const interest = Math.round(principal * INTEREST_RATE * 100) / 100;
  const totalPayable = principal + interest;

  let termDays: number;
  if (principal <= 5000) termDays = 40;
  else if (principal <= 10000) termDays = 60;
  else if (principal <= 20000) termDays = 70;
  else if (principal <= 50000) termDays = 80;
  else if (principal <= 100000) termDays = 120;
  else termDays = 180;

  let installments: number;
  let intervalDays: number;

  if (frequency === 'daily') { intervalDays = 1; installments = termDays; }
  else if (frequency === 'weekly') { intervalDays = 7; installments = Math.ceil(termDays / 7); }
  else { intervalDays = 30; installments = Math.ceil(termDays / 30); }

  const baseInstallment = Math.floor((totalPayable / installments) * 100) / 100;
  const lastInstallment = Math.round((totalPayable - baseInstallment * (installments - 1)) * 100) / 100;

  const now = new Date();
  const schedule = Array.from({ length: installments }, (_, i) => {
    const due = new Date(now);
    due.setDate(due.getDate() + (i + 1) * intervalDays);
    return {
      period: i + 1,
      due_date: due.toISOString().split('T')[0],
      amount: i === installments - 1 ? lastInstallment : baseInstallment,
    };
  });

  return {
    principal,
    interest_rate: INTEREST_RATE * 100,
    interest_amount: interest,
    total_payable: totalPayable,
    term_days: termDays,
    installments,
    installment_amount: baseInstallment,
    frequency,
    schedule,
  };
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;

    const { principal, frequency } = await req.json();

    if (!principal || !frequency) return errorResponse('principal and frequency are required', 400, 'VALIDATION_ERROR');
    if (!validateLoanAmount(Number(principal))) return errorResponse('Amount must be ₱3,000–₱500,000', 400, 'VALIDATION_ERROR');
    if (!validateFrequency(frequency)) return errorResponse('Invalid frequency', 400, 'VALIDATION_ERROR');

    return jsonResponse(computeSchedulePreview(Number(principal), frequency));
  } catch (err) {
    console.error('schedule-preview error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});