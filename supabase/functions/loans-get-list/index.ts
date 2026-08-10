// supabase/functions/loans-get-list/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination } from '../_shared/validators.ts';
import { getLoanFinancialsBatch, getLoanDisbursementsBatch, getLenderAddressBatch, getLoanDisbursementPrefsBatch } from '../_shared/loan_financials.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
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
        payment_frequency, term_days, status, created_at,
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
    if (search) query = query.or(`loan_number.ilike.%${search}%,lender_profiles.users.first_name.ilike.%${search}%,lender_profiles.users.last_name.ilike.%${search}%`);
    if (dateFrom) query = query.gte('created_at', dateFrom);
    if (dateTo) query = query.lte('created_at', dateTo);

    query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);

    const { data, error, count } = await query;
    if (error) return errorResponse('Failed to fetch loans', 500, 'SERVER_ERROR');

    const loanIds = (data ?? []).map((r: any) => r.id);
    const lenderIds = (data ?? []).map((r: any) => r.lender_id);
    const [financials, disbursements, lenderAddresses, disbPrefs] = await Promise.all([
      getLoanFinancialsBatch(db, loanIds),
      getLoanDisbursementsBatch(db, loanIds),
      getLenderAddressBatch(db, lenderIds),
      getLoanDisbursementPrefsBatch(db, loanIds),
    ]);

    const mapped = (data ?? []).map((r: any) => {
      const borrower = r.lender_profiles?.users;
      const fin = financials[r.id] ?? {};
      const disb = disbursements[r.id];
      const pref = disbPrefs[r.id];
      const lenderAddress = lenderAddresses[r.lender_id];
      // Latest credit investigation for the loan (rider assigned for CI).
      const cis = r.credit_investigations ?? [];
      const latestCi = cis.length
        ? cis.sort((a: any, b: any) =>
            (b.created_at ?? '').localeCompare(a.created_at ?? ''))[0]
        : null;
      const ciRider = latestCi?.rider?.users;
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
        status: r.status,
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
      };
    });

    return jsonResponse({ data: mapped, total: count ?? 0, page, limit, totalPages: Math.ceil((count ?? 0) / limit) });
  } catch (err) {
    console.error('loans-get-list error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
