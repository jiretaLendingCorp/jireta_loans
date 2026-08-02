// supabase/functions/in-office-submit/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';

const INTEREST_RATE = 0.20;

function computeSchedule(
  principal: number,
  frequency: 'daily' | 'weekly' | 'monthly',
  startDate: Date
): { due_dates: string[]; amounts: number[]; term_days: number; installment_amount: number } {
  const totalPayable = Math.round(principal * (1 + INTEREST_RATE));
  let termDays: number;
  let installmentCount: number;

  if (frequency === 'daily') {
    termDays = Math.round(principal / 1000) * 10;
    installmentCount = termDays;
  } else if (frequency === 'weekly') {
    const weeks = Math.ceil(principal / 5000) * 2;
    termDays = weeks * 7;
    installmentCount = weeks;
  } else {
    const months = Math.ceil(principal / 10000);
    termDays = months * 30;
    installmentCount = months;
  }

  const installmentAmount = Math.ceil(totalPayable / installmentCount);
  const due_dates: string[] = [];
  const amounts: number[] = [];
  let remaining = totalPayable;

  for (let i = 0; i < installmentCount; i++) {
    const dueDate = new Date(startDate);
    if (frequency === 'daily') dueDate.setDate(dueDate.getDate() + i + 1);
    else if (frequency === 'weekly') dueDate.setDate(dueDate.getDate() + (i + 1) * 7);
    else dueDate.setMonth(dueDate.getMonth() + i + 1);

    due_dates.push(dueDate.toISOString().split('T')[0]);
    const amt = i === installmentCount - 1 ? remaining : Math.min(installmentAmount, remaining);
    amounts.push(amt);
    remaining -= amt;
  }

  return { due_dates, amounts, term_days: termDays, installment_amount: installmentAmount };
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const body = await req.json();
    const { application_id } = body;
    if (!application_id) return errorResponse('application_id is required', 400, 'MISSING_FIELDS');

    const db = getAdminClient();

    const { data: app, error: fetchErr } = await db
      .from('in_office_applications')
      .select('*')
      .eq('id', application_id)
      .single();

    if (fetchErr || !app) return errorResponse('Application not found', 404, 'NOT_FOUND');
    if (authResult.role === ROLES.EMPLOYEE && app.created_by !== authResult.id) {
      return errorResponse('Access denied', 403, 'FORBIDDEN');
    }
    if (app.status === 'converted') return errorResponse('Already converted', 422, 'ALREADY_CONVERTED');

    const s1 = app.step1_data;
    const s2 = app.step2_data;
    const s3 = app.step3_data;
    const s5 = app.step5_data;

    if (!s1 || !s2 || !s3 || !s5) {
      return errorResponse('All 5 steps must be completed before submitting', 422, 'INCOMPLETE_WIZARD');
    }
    if (!s5.signature_base64) {
      return errorResponse('Borrower signature is required', 422, 'SIGNATURE_REQUIRED');
    }

    let lenderId = s1.existing_lender_id;

    if (!lenderId) {
      const lenderData = s1.new_lender;
      const { data: newUser, error: createErr } = await db.auth.admin.createUser({
        phone: lenderData.phone_number,
        password: '12345678',
        user_metadata: { role: 'lender' },
      });
      if (createErr) return errorResponse('Failed to create lender account', 500, 'CREATE_LENDER_ERROR');

      const roleRow = await db.from('roles').select('id').eq('name', ROLES.LENDER).single();

      await db.from('users').insert({
        id: newUser.user.id,
        role_id: roleRow.data?.id,
        first_name: lenderData.first_name,
        last_name: lenderData.last_name,
        phone_number: lenderData.phone_number,
        gender: lenderData.gender,
        civil_status: lenderData.civil_status,
        date_of_birth: lenderData.date_of_birth,
        force_password_change: true,
        account_status: 'active',
      });

      await db.from('lender_profiles').insert({
        user_id: newUser.user.id,
        employment_type: lenderData.employment_type,
        employer_name: lenderData.employer_name,
        monthly_income: lenderData.monthly_income,
        gcash_number: lenderData.gcash_number,
        kyc_status: 'not_submitted',
      });

      lenderId = newUser.user.id;
    }

    const { data: existingLoan } = await db
      .from('loans')
      .select('id')
      .eq('lender_id', lenderId)
      .in('status', ['pending', 'under_review', 'ci_required', 'ci_assigned', 'ci_completed', 'approved', 'active'])
      .single();

    if (existingLoan) return errorResponse('Lender already has an active loan application', 422, 'ACTIVE_LOAN_EXISTS');

    const principal = Number(s3.principal_amount);
    const frequency = s3.payment_frequency;
    const startDate = new Date();
    const schedule = computeSchedule(principal, frequency, startDate);
    const totalPayable = Math.round(principal * 1.2);
    const loanNumber = `LN-${new Date().getFullYear()}-${String(Math.floor(Math.random() * 999999)).padStart(6, '0')}`;

    const { data: loan, error: loanErr } = await db
      .from('loans')
      .insert({
        loan_number: loanNumber,
        lender_id: lenderId,
        processed_by: authResult.id,
        principal_amount: principal,
        interest_rate: INTEREST_RATE,
        interest_amount: Math.round(principal * INTEREST_RATE),
        total_payable: totalPayable,
        outstanding_balance: totalPayable,
        payment_frequency: frequency,
        term_days: schedule.term_days,
        installment_amount: schedule.installment_amount,
        loan_purpose: s3.loan_purpose ?? 'Personal',
        status: 'pending',
        application_source: 'in_office',
      })
      .select()
      .single();

    if (loanErr) return errorResponse('Failed to create loan', 500, 'LOAN_CREATE_ERROR');

    const scheduleRows = schedule.due_dates.map((d, i) => ({
      loan_id: loan.id,
      period_number: i + 1,
      due_date: d,
      amount_due: schedule.amounts[i],
      amount_paid: 0,
      status: 'pending',
    }));
    await db.from('loan_schedules').insert(scheduleRows);

    if (s2.addresses?.length > 0) {
      const addrRows = s2.addresses.map((a: any) => ({ ...a, user_id: lenderId }));
      await db.from('addresses').insert(addrRows);
    }
    if (s2.emergency_contacts?.length > 0) {
      const ecRows = s2.emergency_contacts.map((ec: any) => ({ ...ec, user_id: lenderId }));
      await db.from('emergency_contacts').insert(ecRows);
    }

    const s4 = app.step4_data;
    if (s4?.co_maker) {
      const { data: cm } = await db
        .from('co_makers')
        .insert({ loan_id: loan.id, ...s4.co_maker })
        .select()
        .single();
      if (cm && s4.co_maker_documents?.length > 0) {
        const cmDocRows = s4.co_maker_documents.map((d: any) => ({ ...d, co_maker_id: cm.id }));
        await db.from('co_maker_documents').insert(cmDocRows);
      }
    }

    await db
      .from('in_office_applications')
      .update({ status: 'converted', loan_id: loan.id, submitted_at: new Date().toISOString() })
      .eq('id', application_id);

    const { data: staffUsers } = await db
      .from('users')
      .select('id, fcm_token, roles(name)')
      .in('roles.name', [ROLES.HEAD_MANAGER, ROLES.EMPLOYEE])
      .eq('account_status', 'active');

    for (const su of staffUsers ?? []) {
      await db.from('notifications').insert({
        user_id: su.id,
        title: 'New In-Office Loan Application',
        message: `Loan application ${loanNumber} submitted via in-office wizard.`,
        type: 'loan_application',
        reference_id: loan.id,
        is_read: false,
      });
      if (su.fcm_token) {
        await sendPushNotification(su.fcm_token, 'New Loan Application', `${loanNumber} submitted`, {
          type: 'loan_application',
          loan_id: loan.id,
        });
      }
    }

    await writeAuditLog({
      performedBy: authResult.id,
      action: 'in_office_application_converted',
      tableName: 'in_office_applications',
      recordId: application_id,
      newValues: { loan_id: loan.id, loan_number: loanNumber, lender_id: lenderId },
    });

    return jsonResponse({ success: true, loan_id: loan.id, loan_number: loanNumber });
  } catch (err) {
    console.error('in-office-submit error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});