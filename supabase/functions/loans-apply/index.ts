// supabase/functions/loans-apply/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validateLoanAmount, validateFrequency } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';

const INTEREST_RATE = 0.20;

function computeSchedule(principal: number, frequency: string): {
  totalPayable: number;
  interest: number;
  termDays: number;
  installmentAmount: number;
  installments: number;
  dueDates: string[];
  amounts: number[];
} {
  const interest = Math.round(principal * INTEREST_RATE * 100) / 100;
  const totalPayable = principal + interest;

  let termDays: number;
  let installments: number;
  let intervalDays: number;

  if (principal <= 5000) termDays = 40;
  else if (principal <= 10000) termDays = 60;
  else if (principal <= 20000) termDays = 70;
  else if (principal <= 50000) termDays = 80;
  else if (principal <= 100000) termDays = 120;
  else termDays = 180;

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

  const baseInstallment = Math.floor((totalPayable / installments) * 100) / 100;
  const lastInstallment = Math.round((totalPayable - baseInstallment * (installments - 1)) * 100) / 100;

  const dueDates: string[] = [];
  const amounts: number[] = [];
  const now = new Date();

  for (let i = 0; i < installments; i++) {
    const due = new Date(now);
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

function generateLoanNumber(): string {
  const year = new Date().getFullYear();
  const rand = String(Math.floor(Math.random() * 1000000)).padStart(6, '0');
  return `LN-${year}-${rand}`;
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;

    const roleCheck = requireRole(authResult, ROLES.LENDER);
    if (roleCheck) return roleCheck;

    const body = await req.json();
    const { principal: principalField, principal_amount, frequency, purpose, co_maker } = body;
    const principal = principalField ?? principal_amount;

    if (!principal || !frequency || !purpose) {
      return errorResponse('principal_amount, frequency, and purpose are required', 400, 'VALIDATION_ERROR');
    }
    if (!validateLoanAmount(Number(principal))) {
      return errorResponse('Loan amount must be between ₱3,000 and ₱500,000', 400, 'VALIDATION_ERROR');
    }
    if (!validateFrequency(frequency)) {
      return errorResponse('Invalid frequency. Use: daily, weekly, monthly', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();
    const lenderId = authResult.id;

    const { data: profile } = await db
      .from('lender_profiles')
      .select('kyc_status, is_blacklisted')
      .eq('id', lenderId)
      .single();

    if (!profile) return errorResponse('Lender profile not found', 404, 'NOT_FOUND');
    if (profile.kyc_status !== 'verified') return errorResponse('KYC must be verified before applying', 403, 'KYC_NOT_VERIFIED');
    if (profile.is_blacklisted) return errorResponse('Account is blacklisted', 403, 'BLACKLISTED');

    const { count: activeLoanCount } = await db
      .from('loans')
      .select('*', { count: 'exact', head: true })
      .eq('lender_id', lenderId)
      .in('status', ['pending', 'under_review', 'ci_required', 'ci_assigned', 'ci_completed', 'approved', 'active']);

    if ((activeLoanCount ?? 0) > 0) {
      return errorResponse('You already have an active loan application', 409, 'ACTIVE_LOAN_EXISTS');
    }

    const sched = computeSchedule(Number(principal), frequency);
    const loanNumber = generateLoanNumber();
    const dueDate = sched.dueDates[sched.dueDates.length - 1];

    const { data: loan, error: loanErr } = await db
      .from('loans')
      .insert({
        lender_id: lenderId,
        loan_number: loanNumber,
        principal_amount: Number(principal),
        interest_rate: INTEREST_RATE * 100,
        total_payable: sched.totalPayable,
        outstanding_balance: sched.totalPayable,
        payment_frequency: frequency,
        term_days: sched.termDays,
        purpose: String(purpose).substring(0, 500),
        status: 'pending',
      })
      .select()
      .single();

    if (loanErr || !loan) {
      console.error('Loan insert error:', loanErr);
      return errorResponse('Failed to create loan', 500, 'SERVER_ERROR');
    }

    const scheduleRows = sched.dueDates.map((date, i) => ({
      loan_id: loan.id,
      installment_number: i + 1,
      due_date: date,
      amount_due: sched.amounts[i],
      amount_paid: 0,
      status: 'pending',
    }));

    await db.from('loan_schedules').insert(scheduleRows);

    if (co_maker && co_maker.first_name && co_maker.last_name) {
      const coMakerName = String(co_maker.first_name).trim();
      const coMakerLast = String(co_maker.last_name).trim();
      const dateOfBirth = co_maker.date_of_birth
        ? String(co_maker.date_of_birth).substring(0, 10)
        : null;

      const { data: coMakerRow, error: coErr } = await db
        .from('co_makers')
        .insert({
          loan_id: loan.id,
          first_name: coMakerName,
          last_name: coMakerLast,
          relationship: co_maker.relationship ? String(co_maker.relationship).trim() : 'Other',
          phone_number: co_maker.phone_number ? String(co_maker.phone_number).trim() : null,
          date_of_birth: dateOfBirth,
          address: co_maker.address ? String(co_maker.address).trim() : null,
          signature: co_maker.signature ? String(co_maker.signature) : null,
        })
        .select()
        .single();

      if (coMakerErr || !coMakerRow) {
        console.error('co_maker insert error:', coMakerErr);
        return errorResponse('Failed to save co-maker details', 500, 'SERVER_ERROR');
      }
    }

    await writeAuditLog({
      performedBy: lenderId,
      action: 'loan_applied',
      tableName: 'loans',
      recordId: loan.id,
      newValues: { loan_number: loanNumber, principal: Number(principal), frequency },
      ipAddress: req.headers.get('x-forwarded-for') ?? undefined,
    });

    const { data: staffUsers } = await db
      .from('users')
      .select('id, roles!inner(name)')
      .in('roles.name', ['head_manager', 'employee'])
      .eq('account_status', 'active');

    if (staffUsers) {
      await Promise.all(
        (staffUsers as { id: string }[]).map((u) =>
          sendPushNotification({
            userId: u.id,
            title: 'New Loan Application',
            body: `Loan ${loanNumber} of ₱${Number(principal).toLocaleString()} has been submitted.`,
            type: 'loan_applied',
            referenceId: loan.id,
          })
        )
      );
    }

    return jsonResponse({
      loan_id: loan.id,
      loan_number: loanNumber,
      principal: Number(principal),
      interest: sched.interest,
      total_payable: sched.totalPayable,
      term_days: sched.termDays,
      installment_amount: sched.installmentAmount,
      frequency,
      due_date: dueDate,
      schedule: sched.dueDates.map((d, i) => ({ period: i + 1, due_date: d, amount: sched.amounts[i] })),
    }, 201);
  } catch (err) {
    console.error('loans-apply error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});