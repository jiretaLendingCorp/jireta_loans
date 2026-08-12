// supabase/functions/in-office-view/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   in-office-submit    →  ?fn=submit
//   in-office-get-list  →  ?fn=get-list
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { corsHeaders, handleCors, jsonResponse, errorResponse, successResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { checkPermission, requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { embedAsObject } from '../_shared/types.ts';
import { computeSchedule } from '../_shared/schedule.ts';

// ── [moved from in-office-submit] ───────────────────────────────────────────
// Controlled vocabularies (00025): relationship and document_type are FKs to
// relationship_types / document_types. Draft values are normalized to the
// fallback code so converting an application never trips the FK.
const RELATIONSHIPS = new Set([
  'Spouse', 'Parent', 'Sibling', 'Child', 'Relative',
  'Friend', 'Colleague', 'Employer', 'Other',
]);
const DOCUMENT_TYPES = new Set([
  'valid_id', 'proof_of_income', 'barangay_clearance', 'pay_slip', 'selfie',
  'proof_of_billing', 'certificate_of_employment', 'itr',
  'business_registration', 'co_maker', 'ci_photo', 'evidence', 'site_photo',
  'neighbor_interview', 'proof_of_residence', 'other',
]);

// ── [moved from in-office-submit] ───────────────────────────────────────────
function normalizeRelationship(v?: string | null): string | null {
  if (!v) return null;
  return RELATIONSHIPS.has(v) ? v : 'Other';
}

function normalizeDocumentType(v?: string | null): string | null {
  if (!v) return null;
  return DOCUMENT_TYPES.has(v) ? v : 'other';
}

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'submit';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'submit':
        // ── [moved from functions/in-office-submit/index.ts] ───────────
        return await handleSubmit(req);
      case 'get-list':
        // ── [moved from functions/in-office-get-list/index.ts] ─────────
        return await handleGetList(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('in-office-view error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/in-office-submit/index.ts] ────────────────────────
async function handleSubmit(req: Request) {
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
      .select('id, created_by, status, lender_id, borrower_signature')
      .eq('id', application_id)
      .eq('status', 'draft')
      .single();

    if (appErr || !app) return errorResponse('Application not found or already submitted', 404);

    const canAccess =
      authResult.role === 'head_manager' || app.created_by === authResult.id;
    if (!canAccess) return errorResponse('Access denied', 403, 'FORBIDDEN');

    // Load the normalized wizard data.
    const [personal, employment, addresses, emergencyContacts, loanDetails, coMakerRows, documents] =
      await Promise.all([
        db.from('application_personal_info').select('*').eq('application_id', application_id).maybeSingle(),
        db.from('application_employment_info').select('*').eq('application_id', application_id).maybeSingle(),
        db.from('application_addresses').select('*').eq('application_id', application_id),
        db.from('application_emergency_contacts').select('*').eq('application_id', application_id),
        db.from('application_loan_details').select('*').eq('application_id', application_id).maybeSingle(),
        db.from('application_co_makers').select('*').eq('application_id', application_id),
        db.from('application_documents').select('*').eq('application_id', application_id),
      ]);

    const s1 = personal.data;
    const s2 = { addresses: addresses.data ?? [], emergency_contacts: emergencyContacts.data ?? [] };
    const s3 = loanDetails.data;
    const s4 = coMakerRows.data ?? [];
    const s5 = { documents: documents.data ?? [] };

    if (!s1 || !s3) {
      return errorResponse('Application data is incomplete', 400, 'INCOMPLETE_WIZARD');
    }
    if (Object.keys(s1).length === 0 || !s3.principal_amount) {
      return errorResponse('Step data is incomplete', 400, 'INCOMPLETE_WIZARD');
    }

    let lenderId = app.lender_id ?? null;

    if (!lenderId) {
      const { data: roleRow } = await db.from('roles').select('id').eq('name', 'lender').single();
      const digits = String(s1.phone_number ?? '').replace(/\D/g, '');
      const e164Phone = digits.startsWith('63') ? `+${digits}` : (digits.startsWith('0') ? `+63${digits.slice(1)}` : `+63${digits}`);
      const { data: authUser } = await db.auth.admin.createUser({
        phone: e164Phone,
        password: '12345678',
        phone_confirm: true,
        app_metadata: { role: 'lender' },
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
        id: lenderId,
        gender: s1.gender,
        civil_status: s1.civil_status,
        date_of_birth: s1.date_of_birth,
        employment_type: s1.employment_type ?? employment.data?.employment_type,
        employer_name: s1.employer_name ?? employment.data?.employer_name,
        monthly_income: s1.monthly_income ?? employment.data?.monthly_income,
        gcash_number: s1.gcash_number,
        account_upgrade_status: 'not_submitted',
      });
    }

    if (s2.addresses.length > 0) {
      const addressRows = s2.addresses.map((a) => ({
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

    if (s2.emergency_contacts.length > 0) {
      const ecRows = s2.emergency_contacts.map((ec) => ({
        lender_id: lenderId,
        name: ec.name,
        relationship: normalizeRelationship(ec.relationship ?? null) ?? 'Other',
        phone_number: ec.phone_number,
        address: ec.address,
      }));
      await db.from('emergency_contacts').insert(ecRows);
    }

    const principalAmount = s3.principal_amount;
    const frequency = s3.payment_frequency ?? 'monthly';
    const sched = computeSchedule(Number(principalAmount), frequency);
    const termDays = sched.termDays;
    const dueDates = sched.dueDates;
    const amounts = sched.amounts;

    const releaseDate = new Date();
    const dueDate = new Date(releaseDate);
    dueDate.setDate(dueDate.getDate() + termDays);

    const year = releaseDate.getFullYear();
    const seq = Math.floor(Math.random() * 900000 + 100000);
    const loanNumber = `LN-${year}-${seq}`;

    const { data: loan, error: loanErr } = await db.from('loans').insert({
      lender_id: lenderId,
      in_office_application_id: application_id,
      loan_number: loanNumber,
      principal_amount: principalAmount,
      interest_rate: 20,
      payment_frequency: frequency,
      term_days: termDays,
      status: 'pending',
      purpose: s3.purpose,
    }).select().single();

    if (loanErr || !loan) return errorResponse('Failed to create loan', 500);

    const scheduleRows: {
      loan_id: string;
      installment_number: number;
      due_date: string;
      amount_due: number;
    }[] = dueDates.map((dueDateStr, i) => ({
      loan_id: loan.id,
      installment_number: i + 1,
      due_date: dueDateStr,
      amount_due: amounts[i],
    }));

    await db.from('loan_schedules').insert(scheduleRows);

    for (const coMaker of s4) {
      const { data: person, error: cmErr } = await db.from('co_makers').insert({
        first_name: coMaker.first_name,
        last_name: coMaker.last_name,
        phone_number: coMaker.phone_number,
        date_of_birth: coMaker.date_of_birth,
        address: coMaker.address,
      }).select().single();

      if (cmErr || !person) return errorResponse('Failed to create co-maker', 500);

      await db.from('loan_co_makers').insert({
        loan_id: loan.id,
        co_maker_id: person.id,
        relationship: normalizeRelationship(coMaker.relationship ?? null) ?? 'Other',
      });
    }

    if (s5.documents.length > 0) {
      const docRows = s5.documents.map((d) => ({
        loan_id: loan.id,
        document_type: normalizeDocumentType(d.document_type ?? null) ?? 'other',
        file_path: d.file_path ?? d.file_url,
        file_name: d.file_name ?? 'document',
        mime_type: d.mime_type ?? 'application/octet-stream',
        uploaded_by: authResult.id,
      }));
      await db.from('loan_documents').insert(docRows);
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

    await sendPushNotification({
      userId: lenderId,
      title: 'Loan Application Received',
      body: `Your loan application ${loanNumber} has been submitted for ₱${principalAmount.toLocaleString()}.`,
      type: 'loan_applied',
      referenceId: loan.id,
    });

    return successResponse({
      message: 'Application submitted and converted to loan',
      loan_id: loan.id,
      loan_number: loanNumber,
      lender_id: lenderId,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : undefined;
    return errorResponse(message ?? 'Internal server error', 500);
  }
}

// ── [moved from functions/in-office-get-list/index.ts] ──────────────────────
async function handleGetList(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const roleCheck = requireRole(authResult, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
  if (roleCheck) return roleCheck;

  const db = getAdminClient();
  const url = new URL(req.url);
  const page = parseInt(url.searchParams.get('page') ?? '1');
  const limit = parseInt(url.searchParams.get('limit') ?? '20');
  const status = url.searchParams.get('status');
  const dateFrom = url.searchParams.get('date_from');
  const dateTo = url.searchParams.get('date_to');
  const offset = (page - 1) * limit;

  let query = db
    .from('in_office_applications')
    .select(
      `id, status, wizard_step, created_at, submitted_at, updated_at,
       loan_id,
       personal_info:application_personal_info!application_personal_info_application_id_fkey(
         first_name, last_name, phone_number
       ),
       created_by_user:users!in_office_applications_created_by_fkey(
         id, first_name, last_name, roles(name)
       ),
       loan:loans!in_office_applications_loan_id_fkey(id, loan_number, principal_amount, status)`,
      { count: 'exact' }
    )
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);

  if (authResult.role === ROLES.EMPLOYEE) {
    query = query.eq('created_by', authResult.id);
  }
  if (status) query = query.eq('status', status);
  if (dateFrom) query = query.gte('created_at', dateFrom);
  if (dateTo) query = query.lte('created_at', dateTo);

  const { data, error, count } = await query;
  if (error) return errorResponse('Failed to fetch in-office applications', 500, 'DB_ERROR');

  const rows = (data ?? []).map((row) => {
    const pi = embedAsObject(row.personal_info);
    return {
      ...row,
      lender_name: pi ? `${pi.first_name ?? ''} ${pi.last_name ?? ''}`.trim() : null,
    };
  });

  return jsonResponse({
    data: rows,
    meta: {
      page,
      limit,
      total: count ?? 0,
      total_pages: Math.ceil((count ?? 0) / limit),
    },
  });
}