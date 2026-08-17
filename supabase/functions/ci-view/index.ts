// supabase/functions/ci-view/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes actions through ONE deployable function using
// the `?fn=<action>` query parameter.
//
//   ci-get-list  →  ?fn=get-list
//
// The original action logic is preserved verbatim below.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination } from '../_shared/validators.ts';
import { getLenderAddressBatch } from '../_shared/loan_financials.ts';
import { embedAsObject } from '../_shared/types.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'get-list';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'get-list':
        // ── [moved from functions/ci-get-list/index.ts] ──────────────────
        return await handleCiGetList(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('ci-view error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/ci-get-list/index.ts] ─────────────────────────────
async function handleCiGetList(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  if (user.role === ROLES.LENDER) return errorResponse('Access denied', 403, 'FORBIDDEN');
  const url = new URL(req.url);
  const { page, limit } = validatePagination(url.searchParams.get('page'), url.searchParams.get('limit'));
  const status = url.searchParams.get('status');
  const riderId = url.searchParams.get('rider_id');
  const ciId = url.searchParams.get('ci_id');
  const offset = (page - 1) * limit;
  const db = getAdminClient();
  let query = db.from('credit_investigations')
    .select(`id, status, investigation_notes, deadline, created_at, completed_at, report_summary, response_at,
      loan_id,
      loans(id, loan_number, lender_id, principal_amount, lender_profiles!loans_lender_id_fkey(id, gender, civil_status, date_of_birth, employment_type, employer_name, monthly_income, gcash_number, source_of_funds, account_upgrade_status, users!lender_profiles_id_fkey(id, first_name, middle_name, last_name, phone_number, email, addresses:addresses(address_type, street, barangay, city, province, latitude, longitude)), emergency_contacts(id, name, relationship, phone_number, address))),
      rider:rider_profiles(users!rider_profiles_id_fkey(id, first_name, last_name)),
      assigner:users(id, first_name, last_name),
      ci_documents:ci_documents(id, document_type, file_path, file_name, mime_type, notes, uploaded_at)`, { count: 'exact' });
  if (user.role === ROLES.RIDER) query = query.eq('rider_id', user.id);
  else if (riderId) query = query.eq('rider_id', riderId);
  if (ciId) query = query.eq('id', ciId);
  if (status) query = query.eq('status', status);
  query = query.order('created_at', { ascending: false }).range(offset, offset + limit - 1);
  const { data, error, count } = await query;
  if (error) return errorResponse('Failed to fetch CI list', 500, 'SERVER_ERROR');

  const lenderIds = (data ?? [])
    .map((r) => embedAsObject(r.loans)?.lender_id)
    .filter(Boolean);
  const lenderAddresses = await getLenderAddressBatch(db, lenderIds);

  const rows = await Promise.all(
    (data ?? []).map(async (r) => {
      const loan = embedAsObject(r.loans);
      const lp = loan ? embedAsObject(loan.lender_profiles) : null;
      const users = lp ? embedAsObject(lp.users) : null;
      const lenderId = loan?.lender_id ?? null;

      const rawDocs = Array.isArray(r.ci_documents) ? r.ci_documents : [];
      const ciDocs = [];
      for (const doc of rawDocs) {
        let fileUrl: string | null = null;
        if (doc.file_path) {
          const { data: signedUrl } = await db.storage
            .from('ci-documents')
            .createSignedUrl(doc.file_path, 3600);
          fileUrl = signedUrl?.signedUrl ?? null;
        }
        ciDocs.push({
          ...doc,
          file_url: fileUrl,
          caption: doc.notes ?? null,
        });
      }

      return {
        ...r,
        loans: loan
          ? {
              ...loan,
              lender_name: users
                ? `${users.first_name ?? ''} ${users.last_name ?? ''}`.trim()
                : null,
              lender_profile: lp,
              lender_address: lenderId ? (lenderAddresses[lenderId] ?? null) : null,
            }
          : null,
        ci_documents: ciDocs,
      };
    }),
  );

  return jsonResponse({ data: rows, total: count ?? 0, page, limit, totalPages: Math.ceil((count ?? 0) / limit) });
}