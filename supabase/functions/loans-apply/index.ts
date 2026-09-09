// supabase/functions/loans-apply/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validateLoanAmount, validateFrequency } from '../_shared/validators.ts';
import { computeSchedule, generateLoanNumber, maxPeriodsFor, termDaysFor } from '../_shared/schedule.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { nowManila } from '../_shared/timezone.ts';
import { sanitizeString } from '../_shared/validators.ts';

// ── 00128: per-loan financial + emergency snapshot ─────────────────────────
// Employment / income / emergency contact are declared BY THE BORROWER at
// application time and snapshot onto the loan (loans.* + loan_emergency_contacts).
// They are NOT read from (or written to) lender_profiles for new loans.
const EMPLOYMENT_ALLOWED = [
  'employed', 'self_employed', 'business_owner', 'ofw', 'freelancer',
  'unemployed', 'student', 'other',
];
const RELATIONSHIP_ALLOWED = [
  'Spouse', 'Parent', 'Sibling', 'Child', 'Relative',
  'Friend', 'Colleague', 'Employer', 'Other',
];

function normalizeEnum(value: string | undefined | null): string | null {
  if (!value) return null;
  return sanitizeString(value).trim().toLowerCase().replace(/\s+/g, '_');
}

function cleanPhone(value: string | undefined | null): string | null {
  const digits = sanitizeString(value ?? '').replace(/\D/g, '');
  if (digits.length !== 11 || !digits.startsWith('09')) return null;
  return digits;
}

// 00147: co-maker Valid ID images ride along with the loan application. They
// are uploaded to the private co-maker-documents bucket and linked through
// co_maker_documents so staff reviewers can view them after submission.
function mimeFromExt(ext: string): string {
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'pdf':
      return 'application/pdf';
    default:
      return 'application/octet-stream';
  }
}

// Decode base64 into bytes (whitespace-tolerant, like kyc-submit).
function base64ToBytes(base64: string): Uint8Array {
  const bin = atob(base64.replace(/\s+/g, ''));
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function cleanRelationship(value: string | undefined | null): string {
  if (!value) return 'Other';
  const v = sanitizeString(value).trim();
  if (RELATIONSHIP_ALLOWED.includes(v)) return v;
  // Accept lowercase/snake (e.g. 'spouse') by matching case-insensitively.
  const match = RELATIONSHIP_ALLOWED.find((r) => r.toLowerCase() === v.toLowerCase());
  return match ?? 'Other';
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
    const { principal: principalField, principal_amount, frequency, term_periods, purpose, co_maker, disbursement, employment, emergency_contacts, source_of_funds } = body;
    const principal = principalField ?? principal_amount;

    if (!principal || !frequency || !purpose) {
      return errorResponse('principal_amount, frequency, and purpose are required', 400, 'VALIDATION_ERROR');
    }

    // ── 00128: financial snapshot declared at application time ───────────
    // employment: { type, employer_name, monthly_income } — the borrower's
    // declaration FOR THIS LOAN. Stored on loans, never lender_profiles.
    let employmentType: string | null = null;
    let employerName: string | null = null;
    let monthlyIncome: number | null = null;
    let sourceOfFunds: string | null = null;
    const emp = employment && typeof employment === 'object' ? (employment as Record<string, unknown>) : null;
    if (emp) {
      const rawType = normalizeEnum(emp.type as string | undefined);
      if (!rawType || !EMPLOYMENT_ALLOWED.includes(rawType)) {
        return errorResponse('Invalid employment type', 400, 'VALIDATION_ERROR');
      }
      employmentType = rawType;
      employerName = emp.employer_name
        ? sanitizeString(String(emp.employer_name)).trim().substring(0, 255)
        : null;
      monthlyIncome = emp.monthly_income !== undefined && emp.monthly_income !== null && emp.monthly_income !== ''
        ? Number(emp.monthly_income)
        : NaN;
      if (!employerName) {
        return errorResponse('Employer / business name is required', 400, 'VALIDATION_ERROR');
      }
      if (Number.isNaN(monthlyIncome) || (monthlyIncome as number) <= 0) {
        return errorResponse('Monthly income must be greater than 0', 400, 'VALIDATION_ERROR');
      }
      if (source_of_funds !== undefined && source_of_funds !== null && source_of_funds !== '') {
        sourceOfFunds = normalizeEnum(source_of_funds as string) ?? null;
      }
    }

    // ── 00128: emergency contacts snapshot (loan_emergency_contacts) ──────
    const emergencyRows: Array<{
      name: string;
      relationship: string;
      phone_number: string;
      address: string | null;
    }> = [];
    const rawContacts = Array.isArray(emergency_contacts) ? emergency_contacts as Array<Record<string, unknown>> : [];
    if (rawContacts.length > 0) {
      for (const c of rawContacts) {
        const name = c.name ? sanitizeString(String(c.name)).trim().substring(0, 255) : '';
        const phone = cleanPhone(c.phone_number as string | undefined);
        if (!name || !phone) {
          return errorResponse('Each emergency contact needs a name and a valid phone number (09XXXXXXXXX)', 400, 'VALIDATION_ERROR');
        }
        if (emergencyRows.some((e) => e.phone_number === phone)) {
          return errorResponse('Emergency contact phone numbers must be unique', 400, 'VALIDATION_ERROR');
        }
        emergencyRows.push({
          name,
          relationship: cleanRelationship(c.relationship as string | undefined),
          phone_number: phone,
          address: c.address ? sanitizeString(String(c.address)).trim().substring(0, 1000) : null,
        });
      }
    } else if (emp) {
      // Every application must declare at least one emergency contact.
      return errorResponse('At least one emergency contact is required', 400, 'VALIDATION_ERROR');
    }
    if (!validateLoanAmount(Number(principal))) {
      return errorResponse('Loan amount must be between ₱3,000 and ₱500,000', 400, 'VALIDATION_ERROR');
    }
    if (!validateFrequency(frequency)) {
      return errorResponse('Invalid frequency. Use: daily, weekly, monthly', 400, 'VALIDATION_ERROR');
    }

    let periods: number | undefined;
    if (term_periods !== undefined && term_periods !== null && term_periods !== '') {
      periods = Number(term_periods);
      if (!Number.isInteger(periods) || (periods as number) < 1) {
        return errorResponse('term_periods must be a positive integer', 400, 'VALIDATION_ERROR');
      }
      const maxPeriods = maxPeriodsFor(frequency, termDaysFor(Number(principal)));
      if ((periods as number) > maxPeriods) {
        return errorResponse(`term_periods cannot exceed ${maxPeriods} for this loan and frequency`, 400, 'VALIDATION_ERROR');
      }
    }

    let disbursementMethod: string | null = null;
    let disbursementAccount: string | null = null;
    if (disbursement) {
      const method = String(disbursement.method ?? '').toLowerCase();
      if (method && !['gcash', 'office_cash', 'rider_delivery'].includes(method)) {
        return errorResponse('Invalid disbursement method', 400, 'VALIDATION_ERROR');
      }
      if (method === 'gcash') {
        const gcash = String(disbursement.gcash_number ?? disbursement.gcash ?? '').trim();
        if (!/^09\d{9}$/.test(gcash)) {
          return errorResponse('Valid GCash number is required (09XXXXXXXXX)', 400, 'VALIDATION_ERROR');
        }
        disbursementAccount = gcash;
      }
      disbursementMethod = method || null;
    }

    const db = getAdminClient();
    const lenderId = authResult.id;

    const { data: profile } = await db
      .from('lender_profiles')
      .select('account_upgrade_status')
      .eq('id', lenderId)
      .single();

    if (!profile) return errorResponse('Lender profile not found', 404, 'NOT_FOUND');
    if (profile.account_upgrade_status !== 'verified') return errorResponse('Account upgrade must be completed before applying', 403, 'ACCOUNT_UPGRADE_NOT_VERIFIED');

    const { count: activeLoanCount } = await db
      .from('loans')
      .select('*', { count: 'exact', head: true })
      .eq('lender_id', lenderId)
      .in('status', ['pending', 'under_review', 'ci_required', 'ci_assigned', 'ci_completed', 'approved', 'active']);

    if ((activeLoanCount ?? 0) > 0) {
      return errorResponse('You already have an active loan application', 409, 'ACTIVE_LOAN_EXISTS');
    }

    // 1-month cooldown after rejection: lender cannot re-apply within 1 month of a rejected loan.
    const oneMonthAgo = nowManila();
    oneMonthAgo.setMonth(oneMonthAgo.getMonth() - 1);
    const { data: recentRejected } = await db
      .from('loans')
      .select('updated_at')
      .eq('lender_id', lenderId)
      .eq('status', 'rejected')
      .gte('updated_at', oneMonthAgo.toISOString())
      .order('updated_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (recentRejected) {
      const rejectedAt = new Date(recentRejected.updated_at);
      const cooldownEnd = new Date(rejectedAt);
      cooldownEnd.setMonth(cooldownEnd.getMonth() + 1);
      const remainingDays = Math.ceil((cooldownEnd.getTime() - Date.now()) / (1000 * 60 * 60 * 24));
      return errorResponse(
        `Your previous loan application was rejected. You can re-apply after ${cooldownEnd.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' })} (${remainingDays} days remaining).`,
        403, 'COOLDOWN_ACTIVE'
      );
    }

    const sched = computeSchedule(Number(principal), frequency, new Date(), periods);
    const loanNumber = generateLoanNumber();
    const dueDate = sched.dueDates[sched.dueDates.length - 1];

    const { data: loan, error: loanErr } = await db
      .from('loans')
      .insert({
        lender_id: lenderId,
        loan_number: loanNumber,
        principal_amount: Number(principal),
        interest_rate: 20,
        payment_frequency: frequency,
        term_days: sched.termDays,
        term_periods: sched.installments,
        installment_amount: sched.installmentAmount,
        purpose: String(purpose).substring(0, 500),
        status: 'pending',
        // 00128: per-loan financial snapshot (declared at application time)
        employment_type: employmentType,
        employer_name: employerName,
        monthly_income: monthlyIncome,
        source_of_funds: sourceOfFunds,
      })
      .select()
      .single();

    if (loanErr || !loan) {
      console.error('Loan insert error:', loanErr);
      return errorResponse('Failed to create loan', 500, 'SERVER_ERROR');
    }

    if (disbursementMethod || disbursementAccount) {
      await db.from('loan_disbursement_preferences').insert({
        loan_id: loan.id,
        method: disbursementMethod,
        account: disbursementAccount,
      });
    }

    // 00128: snapshot the declared emergency contacts onto THIS loan.
    if (emergencyRows.length > 0) {
      const { error: ecErr } = await db.from('loan_emergency_contacts').insert(
        emergencyRows.map((ec) => ({ loan_id: loan.id, ...ec })),
      );
      if (ecErr) {
        console.error('loan_emergency_contacts insert error:', ecErr);
        return errorResponse('Failed to save emergency contact details', 500, 'SERVER_ERROR');
      }
    }

    const scheduleRows = sched.dueDates.map((date, i) => ({
      loan_id: loan.id,
      installment_number: i + 1,
      due_date: date,
      amount_due: sched.amounts[i],
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
          first_name: coMakerName,
          last_name: coMakerLast,
          phone_number: co_maker.phone_number ? String(co_maker.phone_number).trim() : null,
          date_of_birth: dateOfBirth,
          address: co_maker.address ? String(co_maker.address).trim() : null,
          signature: co_maker.signature ? String(co_maker.signature) : null,
        })
        .select()
        .single();

      if (coErr || !coMakerRow) {
        console.error('co_maker insert error:', coErr);
        return errorResponse('Failed to save co-maker details', 500, 'SERVER_ERROR');
      }

      const { error: coMakerLinkErr } = await db.from('loan_co_makers').insert({
        loan_id: loan.id,
        co_maker_id: coMakerRow.id,
        relationship: co_maker.relationship ? String(co_maker.relationship).trim() : 'Other',
      });

      if (coMakerLinkErr) {
        console.error('loan_co_makers insert error:', coMakerLinkErr);
        return errorResponse('Failed to save co-maker relationship', 500, 'SERVER_ERROR');
      }

      // 00147: co-maker Valid ID — upload to storage, link via co_maker_documents.
      const validIdDoc = (co_maker as any).valid_id_document;
      if (validIdDoc && validIdDoc.content_base64) {
        const vExt =
          (validIdDoc.file_name ?? 'valid_id.jpg').split('.').pop()?.toLowerCase() ?? 'jpg';
        const vSafeExt = ['jpg', 'jpeg', 'png', 'webp', 'pdf'].includes(vExt)
          ? vExt
          : 'jpg';
        const vObjectPath =
          `co-maker/${coMakerRow.id}/${crypto.randomUUID()}.${vSafeExt}`;
        const vMime = validIdDoc.mime_type ?? mimeFromExt(vSafeExt);

        const { error: vUpErr } = await db.storage
          .from('co-maker-documents')
          .upload(vObjectPath, base64ToBytes(String(validIdDoc.content_base64)), {
            contentType: vMime,
            upsert: false,
          });
        if (vUpErr) {
          console.error('co_maker valid ID upload error:', vUpErr.message);
          return errorResponse(
            `Failed to upload co-maker valid ID: ${vUpErr.message}`,
            500,
            'STORAGE_ERROR',
          );
        }

        const { error: vDocErr } = await db.from('co_maker_documents').insert({
          co_maker_id: coMakerRow.id,
          document_type: 'valid_id',
          file_path: vObjectPath,
          file_name: validIdDoc.file_name ?? 'valid_id.jpg',
          mime_type: vMime,
        });
        if (vDocErr) {
          console.error('co_maker_documents insert error:', vDocErr.message);
          return errorResponse(
            'Failed to save co-maker valid ID document',
            500,
            'SERVER_ERROR',
          );
        }
      }
    }

    await writeAuditLog({
      performedBy: lenderId,
      action: 'loan_applied',
      tableName: 'loans',
      recordId: loan.id,
      newValues: {
        loan_number: loanNumber,
        principal: Number(principal),
        frequency,
        employment_type: employmentType,
        employer_name: employerName,
        monthly_income: monthlyIncome,
        source_of_funds: sourceOfFunds,
        emergency_contacts: emergencyRows,
      },
      ipAddress: req.headers.get('x-forwarded-for') ?? undefined,
    });

    const { data: staffUsers } = await db
      .from('users')
      .select('id, roles!users_role_id_fkey!inner(name)')
      .or('roles.name.eq.head_manager,roles.name.eq.employee')
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
      installments: sched.installments,
      due_dates: sched.dueDates,
      amounts: sched.amounts,
      schedule: sched.periods,
    }, 201);
  } catch (err) {
    console.error('loans-apply error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});