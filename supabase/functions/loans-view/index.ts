// supabase/functions/loans-view/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   loans-get-list             →  ?fn=get-list
//   loans-get-details          →  ?fn=get-details
//   loans-get-schedule-preview →  ?fn=get-schedule-preview
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination, validateLoanAmount, validateFrequency } from '../_shared/validators.ts';
import { getLoanFinancialsBatch, getLoanDisbursementsBatch, getLenderAddressBatch, getLoanDisbursementPrefsBatch, getLoanFinancials, getLoanDisbursement, hasPenaltyApplied } from '../_shared/loan_financials.ts';
import { embedAsObject } from '../_shared/types.ts';
import { computeSchedule, maxPeriodsFor, termDaysFor } from '../_shared/schedule.ts';

// ── [moved from loans-get-schedule-preview] ─────────────────────────────────
const INTEREST_RATE = 0.20;

// ── [moved from loans-get-schedule-preview] ─────────────────────────────────
function computeSchedulePreview(principal: number, frequency: string, periods?: number) {
  const sched = computeSchedule(Number(principal), frequency, new Date(), periods);
  return {
    principal: sched.principal,
    interest_rate: INTEREST_RATE * 100,
    interest: sched.interest,
    interest_amount: sched.interest,
    total_payable: sched.totalPayable,
    term_days: sched.termDays,
    installments: sched.installments,
    max_periods: sched.maxPeriods,
    installment_amount: sched.installmentAmount,
    frequency,
    due_dates: sched.dueDates,
    amounts: sched.amounts,
    schedule: sched.periods,
  };
}

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'get-list';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'get-list':
        // ── [moved from functions/loans-get-list/index.ts] ───────────────
        return await handleGetList(req);
      case 'get-details':
        // ── [moved from functions/loans-get-details/index.ts] ────────────
        return await handleGetDetails(req);
      case 'get-schedule-preview':
        // ── [moved from functions/loans-get-schedule-preview/index.ts] ───
        return await handleGetSchedulePreview(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('loans-view error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/loans-get-list/index.ts] ──────────────────────────
async function handleGetList(req: Request) {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const url = new URL(req.url);
    const { page, limit } = validatePagination(url.searchParams.get('page'), url.searchParams.get('limit'));
    const status = url.searchParams.get('status');
    const search = url.searchParams.get('search');
    const dateFrom = url.searchParams.get('date_from');
    const dateTo = url.searchParams.get('date_to');
    const offset = (page - 1) * limit;

    const db = getAdminClient();
    // The borrower on a loan is a lender_profile (lender_profiles.id = users.id).
    // To reach the user's name we embed lender_profiles → users.
    let query = db.from('loans')
      .select(`id, loan_number, lender_id, principal_amount, interest_rate,
        payment_frequency, term_days, term_periods, installment_amount, status, purpose, created_at,
        updated_at,
        lender_profiles!inner(id, users!lender_profiles_id_fkey(id, first_name, last_name, phone_number)),
        in_office_applications!fk_loans_in_office(created_by),
        credit_investigations(ci_id:id, status, created_at, rider:rider_profiles(users!rider_profiles_id_fkey(first_name, last_name)))`,
        { count: 'exact' });

    if (user.role === ROLES.LENDER) {
      query = query.eq('lender_id', user.id);
    } else if (user.role === ROLES.RIDER) {
      return errorResponse('Access denied', 403, 'FORBIDDEN');
    }
    // head_manager and employee see the full pipeline of loan applications.

    if (status) {
      const statuses = status.split(',').map((s) => s.trim()).filter(Boolean);
      query = query.in('status', statuses);
    }
    if (search) {
      // Strip postgREST filter metacharacters so user input can't break the
      // `.or()` filter (comma, period, parens, wildcard, quotes are all
      // interpreted by the postgREST operator parser).
      const term = String(search).replace(/[(),.%*[\].]/g, '');
      query = query.or(
        `loan_number.ilike.%${term}%,` +
        `lender_profiles.users.first_name.ilike.%${term}%,` +
        `lender_profiles.users.last_name.ilike.%${term}%`,
      );
    }
    if (dateFrom) query = query.gte('created_at', dateFrom);
    if (dateTo) query = query.lte('created_at', dateTo);

    query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);

    const { data, error, count } = await query;
    if (error) return errorResponse('Failed to fetch loans', 500, 'SERVER_ERROR');

    const loanIds = (data ?? []).map((r) => r.id);
    const lenderIds = (data ?? []).map((r) => r.lender_id);
    const [financials, disbursements, lenderAddresses, disbPrefs, upcomingSchedules] = await Promise.all([
      getLoanFinancialsBatch(db, loanIds),
      getLoanDisbursementsBatch(db, loanIds),
      getLenderAddressBatch(db, lenderIds),
      getLoanDisbursementPrefsBatch(db, loanIds),
      // Next outstanding (unpaid) schedule due date per loan. The loans table
      // has no due_date column — it lives on loan_schedules.
      loanIds.length > 0
        ? db.from('v_loan_schedules')
            .select('loan_id, due_date')
            .in('loan_id', loanIds)
            .in('status', ['pending', 'partial', 'overdue'])
            .order('due_date', { ascending: true })
        : Promise.resolve({ data: null }),
    ]);

    const nextDueByLoan: Record<string, string | null> = {};
    for (const s of (upcomingSchedules as { data: Array<{ loan_id: string; due_date: string | null }> | null }).data ?? []) {
      if (s?.loan_id && nextDueByLoan[s.loan_id] === undefined) {
        nextDueByLoan[s.loan_id] = s.due_date ?? null;
      }
    }

    const mapped = (data ?? []).map((r) => {
      const lp = embedAsObject(r.lender_profiles);
      const borrower = lp ? embedAsObject(lp.users) : null;
      const fin = financials[r.id] ?? { interest_amount: null, total_payable: null, outstanding_balance: null };
      const disb = disbursements[r.id];
      const pref = disbPrefs[r.id];
      const lenderAddress = lenderAddresses[r.lender_id];
      // Latest credit investigation for the loan (rider assigned for CI).
      const cis = r.credit_investigations ?? [];
      const latestCi = cis.length
        ? cis.sort((a, b) =>
            (b.created_at ?? '').localeCompare(a.created_at ?? ''))[0]
        : null;
      const ciRiderEmbed = latestCi ? embedAsObject(latestCi.rider) : null;
      const ciRider = ciRiderEmbed ? embedAsObject(ciRiderEmbed.users) : null;
      return {
        id: r.id,
        loan_number: r.loan_number,
        lender_id: r.lender_id,
        lender_name: borrower
          ? `${borrower.first_name} ${borrower.last_name}`.trim()
          : null,
        principal_amount: r.principal_amount,
        interest_rate: r.interest_rate,
        interest_amount: fin.interest_amount ?? null,
        total_payable: fin.total_payable ?? null,
        outstanding_balance: fin.outstanding_balance ?? null,
        payment_frequency: r.payment_frequency,
        frequency: r.payment_frequency,
        term_days: r.term_days,
        term_periods: r.term_periods,
        installment_amount: r.installment_amount,
        status: r.status,
        due_date: nextDueByLoan[r.id] ?? null,
        created_at: r.created_at,
        disbursed_at: disb?.disbursed_at ?? null,
        updated_at: r.updated_at,
        disbursement_method: pref?.method ?? null,
        disbursement_account: pref?.account ?? null,
        lender_address: lenderAddress ?? null,
        ci_status: latestCi?.status ?? null,
        assigned_rider_name: ciRider
          ? `${ciRider.first_name} ${ciRider.last_name}`.trim()
          : null,
        rider_delivery_assigned: disb?.method === 'rider_delivery',
      };
    });

    return jsonResponse({ data: mapped, total: count ?? 0, page, limit, totalPages: Math.ceil((count ?? 0) / limit) });
}

// ── [moved from functions/loans-get-details/index.ts] ───────────────────────
async function handleGetDetails(req: Request) {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const url = new URL(req.url);
    const loanId = url.searchParams.get('loan_id');
    if (!loanId) return errorResponse('loan_id is required', 400, 'VALIDATION_ERROR');

    const db = getAdminClient();

    const { data: loan } = await db.from('loans')
      .select(`*, lender_profiles!loans_lender_id_fkey(id, account_upgrade_status, gcash_number, employment_type, employer_name, monthly_income, users:users!lender_profiles_id_fkey(id, first_name, middle_name, last_name, phone_number, email))`)
      .eq('id', loanId).single();

    if (!loan) return errorResponse('Loan not found', 404, 'NOT_FOUND');
    if (user.role === ROLES.LENDER && loan.lender_id !== user.id) return errorResponse('Access denied', 403, 'FORBIDDEN');
    if (user.role === ROLES.RIDER) return errorResponse('Access denied', 403, 'FORBIDDEN');

    const { data: schedule } = await db.from('v_loan_schedules').select('*').eq('loan_id', loanId).order('installment_number');
    // Next outstanding (unpaid) schedule due date — the loans table itself has
    // no due_date column, it lives on loan_schedules.
    const { data: nextSched } = await db
      .from('v_loan_schedules')
      .select('due_date')
      .eq('loan_id', loanId)
      .in('status', ['pending', 'partial', 'overdue'])
      .order('due_date', { ascending: true })
      .limit(1)
      .maybeSingle();
    const scheduleIds = (schedule ?? []).map((s) => s.id);
    let payments: Record<string, unknown>[] = [];
    if (scheduleIds.length > 0) {
      const { data: payRows } = await db.from('payments').select('*').in('loan_schedule_id', scheduleIds).order('created_at', { ascending: false });
      payments = payRows ?? [];
    }
    const { data: ci } = await db.from('credit_investigations').select('*').eq('loan_id', loanId).order('created_at', { ascending: false });
    const { data: disbursements } = await db.from('disbursements').select('*').eq('loan_id', loanId).order('created_at', { ascending: false });
    const { data: penalties } = await db.from('penalty_logs').select('*').eq('loan_id', loanId).order('applied_at', { ascending: false });
    const { data: coMakerLinks } = await db
      .from('loan_co_makers')
      .select('relationship, co_maker:co_makers(*)')
      .eq('loan_id', loanId)
      .order('created_at');

    const coMakers = (coMakerLinks ?? []).map((link) => ({
      ...(link.co_maker ?? {}),
      relationship: link.relationship,
    }));

    const [financials, disbursement, penaltyApplied, disbPref] = await Promise.all([
      getLoanFinancials(db, loanId),
      getLoanDisbursement(db, loanId),
      hasPenaltyApplied(db, loanId),
      db.from('loan_disbursement_preferences').select('method, account').eq('loan_id', loanId).maybeSingle(),
    ]);

    const lp = loan?.lender_profiles;
    const loanOut: Record<string, unknown> = {
      ...loan,
      due_date: nextSched?.due_date ?? null,
      total_payable: financials?.total_payable ?? null,
      outstanding_balance: financials?.outstanding_balance ?? null,
      interest_amount: financials?.interest_amount ?? null,
      penalty_applied: penaltyApplied,
      disbursed_at: disbursement?.disbursed_at ?? null,
      disbursement_method: disbPref?.data?.method ?? disbursement?.method ?? null,
      disbursement_account: disbPref?.data?.account ?? null,
      xendit_disbursement_id: disbursement?.xendit_id ?? null,
      frequency: loan.payment_frequency,
      lender: lp?.users ?? null,
      lender_profile: lp ?? null,
      loan_schedules: schedule ?? [],
      payments: payments,
      credit_investigations: ci ?? [],
      disbursements: disbursements ?? [],
      ci_status: (ci ?? []).length > 0 ? (ci ?? [])[0]?.status ?? null : null,
      rider_delivery_assigned: (disbursements ?? []).some(
        (d) => d?.method === 'rider_delivery'),
      penalties: penalties ?? [],
      co_makers: coMakers ?? [],
    };

    return jsonResponse(loanOut);
}

// ── [moved from functions/loans-get-schedule-preview/index.ts] ──────────────
async function handleGetSchedulePreview(req: Request) {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;

    const { principal, frequency, term_periods } = await req.json();

    if (!principal || !frequency) return errorResponse('principal and frequency are required', 400, 'VALIDATION_ERROR');
    if (!validateLoanAmount(Number(principal))) return errorResponse('Amount must be ₱3,000–₱500,000', 400, 'VALIDATION_ERROR');
    if (!validateFrequency(frequency)) return errorResponse('Invalid frequency', 400, 'VALIDATION_ERROR');

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

    return jsonResponse(computeSchedulePreview(Number(principal), frequency, periods));
}