// supabase/functions/in-office-submit/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders, errorResponse, successResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { checkPermission } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;

  const permCheck = checkPermission(authResult.role, 'in_office', 'submit');
  if (permCheck) return permCheck;

  if (req.method !== 'POST') return errorResponse('Method not allowed', 405);

  try {
    const { application_id } = await req.json();
    if (!application_id) return errorResponse('application_id is required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();

    const { data: app, error: appErr } = await db
      .from('in_office_applications')
      .select('*, step1_data, step2_data, step3_data, step4_data, step5_data')
      .eq('id', application_id)
      .eq('status', 'draft')
      .single();

    if (appErr || !app) return errorResponse('Application not found or already submitted', 404);

    const canAccess =
      authResult.role === 'head_manager' || app.created_by === authResult.id;
    if (!canAccess) return errorResponse('Access denied', 403, 'FORBIDDEN');

    for (let step = 1; step <= 5; step++) {
      if (!app[`step${step}_data`] || Object.keys(app[`step${step}_data`]).length === 0) {
        return errorResponse(`Step ${step} data is incomplete`, 400, 'INCOMPLETE_WIZARD');
      }
    }

    const s1 = app.step1_data;
    const s2 = app.step2_data;
    const s3 = app.step3_data;
    const s4 = app.step4_data;
    const s5 = app.step5_data;

    let lenderId = s1.lender_id;

    if (!lenderId) {
      const { data: roleRow } = await db.from('roles').select('id').eq('name', 'lender').single();
      const { data: authUser } = await db.auth.admin.createUser({
        phone: s1.phone_number,
        password: '12345678',
        phone_confirm: true,
      });
      if (!authUser?.user) return errorResponse('Failed to create lender auth account', 500);

      const { data: newUser, error: userErr } = await db.from('users').insert({
        id: authUser.user.id,
        role_id: roleRow?.id,
        phone_number: s1.phone_number,
        first_name: s1.first_name,
        last_name: s1.last_name,
        middle_name: s1.middle_name,
        account_status: 'active',
        force_password_change: true,
        created_by: authResult.id,
      }).select().single();

      if (userErr) return errorResponse('Failed to create lender user', 500);
      lenderId = newUser.id;

      await db.from('lender_profiles').insert({
        user_id: lenderId,
        gender: s1.gender,
        civil_status: s1.civil_status,
        date_of_birth: s1.date_of_birth,
        employment_type: s1.employment_type,
        employer_name: s1.employer_name,
        monthly_income: s1.monthly_income,
        gcash_number: s1.gcash_number,
        kyc_status: 'pending',
        is_blacklisted: false,
      });
    }

    if (s2.addresses) {
      const addressRows = (s2.addresses as any[]).map((a: any) => ({
        user_id: lenderId,
        address_type: a.address_type,
        street: a.street,
        barangay: a.barangay,
        city: a.city,
        province: a.province,
        zip_code: a.zip_code,
        latitude: a.latitude,
        longitude: a.longitude,
      }));
      await db.from('addresses').insert(addressRows);
    }

    if (s2.emergency_contacts) {
      const ecRows = (s2.emergency_contacts as any[]).map((ec: any) => ({
        user_id: lenderId,
        full_name: ec.full_name,
        relationship: ec.relationship,
        contact_number: ec.contact_number,
        address: ec.address,
      }));
      await db.from('emergency_contacts').insert(ecRows);
    }

    const interestRate = 0.20;
    const principalAmount = s3.principal_amount;
    const frequency = s3.frequency;
    const interestAmount = principalAmount * interestRate;
    const totalPayable = principalAmount + interestAmount;

    let termDays = 30;
    let installmentAmount = totalPayable;

    if (frequency === 'daily') {
      termDays = Math.ceil(principalAmount / 1000) * 10;
      installmentAmount = parseFloat((totalPayable / termDays).toFixed(2));
    } else if (frequency === 'weekly') {
      const weeks = Math.ceil(principalAmount / 5000) * 2;
      termDays = weeks * 7;
      installmentAmount = parseFloat((totalPayable / weeks).toFixed(2));
    } else {
      const months = Math.ceil(principalAmount / 10000);
      termDays = months * 30;
      installmentAmount = parseFloat((totalPayable / months).toFixed(2));
    }

    const releaseDate = new Date();
    const dueDate = new Date(releaseDate);
    dueDate.setDate(dueDate.getDate() + termDays);

    const year = releaseDate.getFullYear();
    const seq = Math.floor(Math.random() * 900000 + 100000);
    const loanNumber = `LN-${year}-${seq}`;

    const { data: loan, error: loanErr } = await db.from('loans').insert({
      lender_id: lenderId,
      loan_number: loanNumber,
      principal_amount: principalAmount,
      interest_rate: interestRate,
      interest_amount: interestAmount,
      total_payable: totalPayable,
      outstanding_balance: totalPayable,
      frequency,
      term_days: termDays,
      release_date: releaseDate.toISOString().split('T')[0],
      due_date: dueDate.toISOString().split('T')[0],
      status: 'pending',
      purpose: s3.purpose,
      penalty_applied: false,
      created_by: authResult.id,
    }).select().single();

    if (loanErr || !loan) return errorResponse('Failed to create loan', 500);

    const scheduleRows: any[] = [];
    if (frequency === 'daily') {
      for (let i = 0; i < termDays; i++) {
        const d = new Date(releaseDate);
        d.setDate(d.getDate() + i + 1);
        scheduleRows.push({
          loan_id: loan.id,
          period_number: i + 1,
          due_date: d.toISOString().split('T')[0],
          amount_due: installmentAmount,
          amount_paid: 0,
          status: 'pending',
        });
      }
    } else if (frequency === 'weekly') {
      const weeks = Math.round(termDays / 7);
      for (let i = 0; i < weeks; i++) {
        const d = new Date(releaseDate);
        d.setDate(d.getDate() + (i + 1) * 7);
        scheduleRows.push({
          loan_id: loan.id,
          period_number: i + 1,
          due_date: d.toISOString().split('T')[0],
          amount_due: installmentAmount,
          amount_paid: 0,
          status: 'pending',
        });
      }
    } else {
      const months = Math.round(termDays / 30);
      for (let i = 0; i < months; i++) {
        const d = new Date(releaseDate);
        d.setMonth(d.getMonth() + i + 1);
        const lastDay = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
        d.setDate(lastDay);
        scheduleRows.push({
          loan_id: loan.id,
          period_number: i + 1,
          due_date: d.toISOString().split('T')[0],
          amount_due: installmentAmount,
          amount_paid: 0,
          status: 'pending',
        });
      }
    }

    await db.from('loan_schedules').insert(scheduleRows);

    if (s4 && s4.first_name) {
      const { data: coMaker } = await db.from('co_makers').insert({
        loan_id: loan.id,
        first_name: s4.first_name,
        middle_name: s4.middle_name,
        last_name: s4.last_name,
        relationship: s4.relationship,
        contact_number: s4.contact_number,
        address: s4.address,
        birthday: s4.birthday,
      }).select().single();

      if (coMaker && s4.documents) {
        const docRows = (s4.documents as any[]).map((d: any) => ({
          co_maker_id: coMaker.id,
          document_type: d.document_type,
          file_url: d.file_url,
        }));
        await db.from('co_maker_documents').insert(docRows);
      }
    }

    await db.from('in_office_applications')
      .update({ status: 'converted', loan_id: loan.id, wizard_step: 5, updated_at: new Date().toISOString() })
      .eq('id', application_id);

    await writeAuditLog({
      performedBy: authResult.id,
      action: 'in_office_submitted',
      tableName: 'in_office_applications',
      recordId: application_id,
      newValues: { loan_id: loan.id, lender_id: lenderId, loan_number: loanNumber },
    });

    await sendPushNotification(db, {
      user_id: lenderId,
      title: 'Loan Application Received',
      body: `Your loan application ${loanNumber} has been submitted for ₱${principalAmount.toLocaleString()}.`,
      type: 'loan_applied',
      reference_id: loan.id,
    });

    return successResponse({
      message: 'Application submitted and converted to loan',
      loan_id: loan.id,
      loan_number: loanNumber,
      lender_id: lenderId,
    });
  } catch (err: any) {
    return errorResponse(err.message ?? 'Internal server error', 500);
  }
});