// supabase/functions/kyc-get-details/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { getLenderBlacklist, getLenderAddress } from '../_shared/loan_financials.ts';

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

    const [blacklist, address] = await Promise.all([
      getLenderBlacklist(db, targetLenderId!),
      getLenderAddress(db, targetLenderId!),
    ]);

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
      is_blacklisted: blacklist ? true : null,
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
  } catch (err) {
    console.error('kyc-get-details error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
