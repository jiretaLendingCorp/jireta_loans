// supabase/functions/kyc-get-list/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination } from '../_shared/validators.ts';
import { getLenderBlacklistBatch, getLenderAddressBatch } from '../_shared/loan_financials.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const url = new URL(req.url);
    const { page, limit } = validatePagination(url.searchParams.get('page'), url.searchParams.get('limit'));
    const status = url.searchParams.get('status');
    // Accept both spellings used by the app.
    const search = url.searchParams.get('search') ?? url.searchParams.get('lender_name');
    const offset = (page - 1) * limit;

    const db = getAdminClient();

    let query = db.from('lender_profiles')
      .select(`
        id, kyc_status,
        source_of_funds, gender, civil_status, date_of_birth, employment_type,
        employer_name, monthly_income, gcash_number,
        users!lender_profiles_id_fkey(id, first_name, middle_name, last_name, suffix, phone_number, email, account_status, profile_photo_url),
        kyc_documents(id, document_type, file_path, status, uploaded_at, rejection_notes, reviewed_by, reviewed_at),
        emergency_contacts(id, name, relationship, phone_number, address)
      `, { count: 'exact' })
      .neq('kyc_status', 'not_submitted');

    if (status) query = query.eq('kyc_status', status);
    if (search) query = query.or(`users.first_name.ilike.%${search}%,users.last_name.ilike.%${search}%,users.middle_name.ilike.%${search}%`);

    const { data, error, count } = await query
      .order('updated_at', { ascending: false })
      .range(offset, offset + limit - 1);
    if (error) return errorResponse(`Failed to fetch KYC list: ${error.message}`, 500, 'SERVER_ERROR');

    const rows = data ?? [];
    const lenderIds = rows.map((r: any) => r.id);
    const [blacklistMap, addressMap] = await Promise.all([
      getLenderBlacklistBatch(db, lenderIds),
      getLenderAddressBatch(db, lenderIds),
    ]);

    // One row per lender (NOT one per document). Staff should see a single
    // submission per borrower with a document count; document-level review
    // happens inside kyc-get-details / kyc-verify. `id` is the lender id so
    // the client can navigate straight to the lender's KYC details.
    const mapped = (rows ?? []).map((row: any) => {
      const address = addressMap[row.id] ?? null;
      const isBlacklisted = Boolean(blacklistMap[row.id]);
      const lender = {
        id: row.users?.id ?? row.id,
        first_name: row.users?.first_name,
        middle_name: row.users?.middle_name,
        last_name: row.users?.last_name,
        suffix: row.users?.suffix,
        phone_number: row.users?.phone_number,
        email: row.users?.email,
        account_status: row.users?.account_status,
        profile_photo_url: row.users?.profile_photo_url,
        kyc_status: row.kyc_status,
        street_address: address?.street ?? null,
        barangay: address?.barangay ?? null,
        city: address?.city ?? null,
        province: address?.province ?? null,
        zip_code: address?.zip_code ?? null,
        source_of_funds: row.source_of_funds,
        gender: row.gender,
        civil_status: row.civil_status,
        date_of_birth: row.date_of_birth,
        employment_type: row.employment_type,
        employer_name: row.employer_name,
        monthly_income: row.monthly_income,
        gcash_number: row.gcash_number,
        is_blacklisted: isBlacklisted,
      };

      const docs = row.kyc_documents ?? [];
      const docTypes = [...new Set(docs.map((d: any) => d.document_type))];
      const latestUpload = docs.length
        ? docs.reduce((a: any, b: any) =>
            (a.uploaded_at ?? '') > (b.uploaded_at ?? '') ? a : b)
        : null;

      return {
        id: row.id,
        lender_id: row.id,
        document_type: 'submission',
        document_count: docs.length,
        document_types: docTypes,
        file_url: null,
        status: row.kyc_status ?? (docs.length ? 'submitted' : 'not_submitted'),
        created_at: latestUpload?.uploaded_at ?? row.updated_at ?? new Date().toISOString(),
        lender,
        emergency_contacts: row.emergency_contacts ?? [],
      };
    });

    return jsonResponse({
      data: mapped,
      total: count ?? mapped.length,
      page,
      limit,
      totalPages: limit > 0 ? Math.ceil((count ?? mapped.length) / limit) : 1,
    });
  } catch (err) {
    console.error('kyc-get-list error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
