// supabase/functions/kyc-view/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   kyc-verify       →  ?fn=verify
//   kyc-get-list     →  ?fn=get-list
//   kyc-get-status   →  ?fn=get-status
//   kyc-get-details  →  ?fn=get-details
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { sendPushNotification } from '../_shared/notifications.ts';
import { getLenderAddressBatch, getLenderAddress } from '../_shared/loan_financials.ts';

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'verify';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'verify':
        // ── [moved from functions/kyc-verify/index.ts] ───────────────────
        return await handleVerify(req);
      case 'get-list':
        // ── [moved from functions/kyc-get-list/index.ts] ─────────────────
        return await handleGetList(req);
      case 'get-status':
        // ── [moved from functions/kyc-get-status/index.ts] ───────────────
        return await handleGetStatus(req);
      case 'get-details':
        // ── [moved from functions/kyc-get-details/index.ts] ──────────────
        return await handleGetDetails(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('kyc-view error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/kyc-verify/index.ts] ──────────────────────────────
async function handleVerify(req: Request) {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const body = await req.json();
    const { kyc_doc_id, lender_id, action, rejection_notes } = body;
    if (!['verified', 'rejected'].includes(action)) {
      return errorResponse('action (verified|rejected) is required', 400, 'VALIDATION_ERROR');
    }
    if (action === 'rejected' && !rejection_notes) {
      return errorResponse('rejection_notes required when rejecting', 400, 'VALIDATION_ERROR');
    }
    if (!kyc_doc_id && !lender_id) {
      return errorResponse('kyc_doc_id or lender_id is required', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
    const now = new Date().toISOString();

    // Resolve the lender_id: direct lender_id, or from a single document id.
    let targetLenderId = lender_id as string | null;
    let singleDocId: string | null = null;
    if (kyc_doc_id) {
      const { data: doc } = await db.from('kyc_documents').select('id, lender_id, status').eq('id', kyc_doc_id).single();
      if (!doc) return errorResponse('KYC document not found', 404, 'NOT_FOUND');
      targetLenderId = (doc as any).lender_id;
      singleDocId = kyc_doc_id;
    }

    // When lender_id is given, verify/reject ALL non-final docs for that lender
    // in a single operation. When kyc_doc_id is given, only that doc is updated.
    let query = db.from('kyc_documents').update({
      status: action,
      reviewed_by: user.id,
      reviewed_at: now,
      rejection_notes: rejection_notes ?? null,
    }).eq('lender_id', targetLenderId);
    if (singleDocId) query = query.eq('id', singleDocId);
    const { error: updateError } = await query;
    if (updateError) return errorResponse('Failed to update KYC documents', 500, 'DB_ERROR');

    const { data: allDocs } = await db.from('kyc_documents').select('status').eq('lender_id', targetLenderId);
    const anyRejected = allDocs?.some((d: any) => d.status === 'rejected');
    const allVerified = allDocs?.every((d: any) => d.status === 'verified');

    let newKycStatus = 'submitted';
    if (anyRejected) newKycStatus = 'rejected';
    else if (allVerified) newKycStatus = 'verified';

    await db.from('lender_profiles').update({ kyc_status: newKycStatus }).eq('id', targetLenderId);

    await writeAuditLog({
      performedBy: user.id,
      action: singleDocId ? `kyc_doc_${action}` : `kyc_all_${action}`,
      tableName: 'kyc_documents',
      recordId: singleDocId ?? targetLenderId,
      ipAddress: ip,
    });
    await sendPushNotification({
      userId: targetLenderId,
      title: action === 'verified' ? 'KYC Verified' : 'KYC Rejected',
      body: action === 'verified'
        ? 'All of your KYC documents have been verified.'
        : `KYC rejected: ${rejection_notes}`,
      type: 'kyc_update',
      referenceId: singleDocId ?? targetLenderId,
      sentBy: user.id,
    });

    return jsonResponse({
      message: singleDocId ? `Document ${action}` : `All documents ${action}`,
      kyc_status: newKycStatus,
      lender_id: targetLenderId,
    });
}

// ── [moved from functions/kyc-get-list/index.ts] ────────────────────────────
async function handleGetList(req: Request) {
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
    const addressMap = await getLenderAddressBatch(db, lenderIds);

    // One row per lender (NOT one per document). Staff should see a single
    // submission per borrower with a document count; document-level review
    // happens inside kyc-get-details / kyc-verify. `id` is the lender id so
    // the client can navigate straight to the lender's KYC details.
    const mapped = (rows ?? []).map((row: any) => {
      const address = addressMap[row.id] ?? null;
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
}

// ── [moved from functions/kyc-get-status/index.ts] ──────────────────────────
async function handleGetStatus(req: Request) {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.LENDER, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const url = new URL(req.url);
    const requestedLenderId = url.searchParams.get('lender_id');

    // Lenders may only ever inspect their own KYC; ignore any lender_id they send.
    let lenderId = user.id;
    if (user.role !== ROLES.LENDER) {
      if (requestedLenderId) {
        const roleCheck2 = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
        if (roleCheck2) return roleCheck2;
        lenderId = requestedLenderId;
      }
    }

    const db = getAdminClient();
    const { data: profile } = await db.from('lender_profiles').select('*').eq('id', lenderId).single();
    const { data: docs } = await db.from('kyc_documents')
      .select('id, lender_id, document_type, file_path, status, rejection_notes, reviewed_by, reviewed_at, uploaded_at')
      .eq('lender_id', lenderId)
      .order('uploaded_at', { ascending: false });
    const { data: emergencyContacts } = await db.from('emergency_contacts')
      .select('id, name, relationship, phone_number, address')
      .eq('lender_id', lenderId);

    const address = await getLenderAddress(db, lenderId);

    const lender = profile
      ? {
          ...profile,
          street_address: address?.street ?? null,
          barangay: address?.barangay ?? null,
          city: address?.city ?? null,
          province: address?.province ?? null,
          zip_code: address?.zip_code ?? null,
        }
      : null;

    const documents = (docs ?? []).map((d: any) => ({
      ...d,
      file_url: d.file_path,
      created_at: d.uploaded_at,
    }));

    return jsonResponse({
      kyc_status: profile?.kyc_status ?? 'not_submitted',
      lender_id: lenderId,
      lender,
      documents,
      emergency_contacts: emergencyContacts ?? [],
    });
}

// ── [moved from functions/kyc-get-details/index.ts] ─────────────────────────
async function handleGetDetails(req: Request) {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.HEAD_MANAGER, ROLES.EMPLOYEE);
    if (roleCheck) return roleCheck;

    const url = new URL(req.url);
    const kycDocId = url.searchParams.get('kyc_doc_id');
    const lenderId = url.searchParams.get('lender_id');

    if (!kycDocId && !lenderId) {
      return errorResponse('kyc_doc_id or lender_id is required', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();

    // Resolve the lender_id from either the document id or a direct lender id.
    let targetLenderId = lenderId;
    let document: any = null;
    if (kycDocId) {
      const { data: raw, error } = await db
        .from('kyc_documents')
        .select('id, lender_id, document_type, file_path, file_name, status, rejection_notes, reviewed_by, reviewed_at, uploaded_at')
        .eq('id', kycDocId)
        .single();
      if (error || !raw) return errorResponse('KYC document not found', 404, 'NOT_FOUND');
      targetLenderId = (raw as any).lender_id;
      document = {
        id: (raw as any).id,
        lender_id: (raw as any).lender_id,
        document_type: (raw as any).document_type,
        file_url: (raw as any).file_path,
        file_name: (raw as any).file_name,
        status: (raw as any).status,
        created_at: (raw as any).uploaded_at,
        rejection_notes: (raw as any).rejection_notes,
        reviewed_by: (raw as any).reviewed_by,
        reviewed_at: (raw as any).reviewed_at,
      };
    }

    // lender_id points at lender_profiles.id which equals the users.id PK.
    const { data: userRow } = await db
      .from('users')
      .select('id, first_name, middle_name, last_name, suffix, phone_number, email, account_status, profile_photo_url, created_at')
      .eq('id', targetLenderId!)
      .single();

    const { data: lenderProfile } = await db
      .from('lender_profiles')
      .select('*')
      .eq('id', targetLenderId!)
      .single();

    const { data: docs } = await db
      .from('kyc_documents')
      .select('id, lender_id, document_type, file_path, file_name, status, rejection_notes, reviewed_by, reviewed_at, uploaded_at')
      .eq('lender_id', targetLenderId!)
      .order('uploaded_at', { ascending: false });

    // kyc-documents is a private bucket with an owner-scoped RLS policy
    // (only the lender who uploaded a file may read it). Staff review KYC
    // with their own JWT, so a client-side signed URL lookup would be blocked
    // by RLS and fail with "object not found". Resolve signed URLs here with
    // the service-role client so reviewers can open lender documents.
    const KYC_BUCKET = 'kyc-documents';
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const signOne = async (path: string) => {
      const { data } = await db.storage
        .from(KYC_BUCKET)
        .createSignedUrl(path, 3600);
      // createSignedUrl already returns an absolute URL (e.g.
      // http://localhost:8000/storage/v1/object/sign/...). Only prefix with the
      // storage base URL when the SDK returns a bare relative path so we never
      // produce a doubled URL like .../storage/v1http://.../storage/v1/object.
      const signedPath = (data as any)?.signedUrl as string | null ?? null;
      if (!signedPath) return null;
      return signedPath.startsWith('http')
        ? signedPath
        : `${supabaseUrl}/storage/v1${signedPath}`;
    };
    const signedUrls = new Map<string, string | null>();
    for (const d of (docs ?? [])) {
      const p = (d as any).file_path as string;
      if (p) signedUrls.set((d as any).id, await signOne(p));
    }

    const { data: emergencyContacts } = await db
      .from('emergency_contacts')
      .select('id, name, relationship, phone_number, address')
      .eq('lender_id', targetLenderId!);

    const address = await getLenderAddress(db, targetLenderId!);

    const lender = {
      id: (userRow as any)?.id ?? targetLenderId,
      first_name: (userRow as any)?.first_name,
      middle_name: (userRow as any)?.middle_name,
      last_name: (userRow as any)?.last_name,
      suffix: (userRow as any)?.suffix,
      phone_number: (userRow as any)?.phone_number,
      email: (userRow as any)?.email,
      account_status: (userRow as any)?.account_status,
      profile_photo_url: (userRow as any)?.profile_photo_url,
      created_at: (userRow as any)?.created_at,
      ...(lenderProfile as any ?? {}),
      street_address: address?.street ?? null,
      barangay: address?.barangay ?? null,
      city: address?.city ?? null,
      province: address?.province ?? null,
      zip_code: address?.zip_code ?? null,
    };

    const documents = (docs ?? []).map((d: any) => ({
      id: d.id,
      lender_id: d.lender_id,
      document_type: d.document_type,
      file_url: d.file_path,
      file_name: d.file_name,
      status: d.status,
      created_at: d.uploaded_at,
      rejection_notes: d.rejection_notes,
      reviewed_by: d.reviewed_by,
      reviewed_at: d.reviewed_at,
      signed_url: signedUrls.get(d.id) ?? null,
    }));

    return jsonResponse({
      document,
      lender_id: targetLenderId,
      kyc_status: (lenderProfile as any)?.kyc_status ?? 'not_submitted',
      lender,
      documents,
      emergency_contacts: emergencyContacts ?? [],
    });
}