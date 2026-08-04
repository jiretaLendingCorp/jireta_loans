
// supabase/functions/kyc-get-list/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { validatePagination } from '../_shared/validators.ts';

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
    const search = url.searchParams.get('search');
    const offset = (page - 1) * limit;

    const db = getAdminClient();
    let query = db.from('lender_profiles')
      .select(`id, kyc_status, users!lender_profiles_id_fkey(id, first_name, last_name, phone_number, account_status), 
        kyc_documents(id, document_type, file_path, status, uploaded_at)`, { count: 'exact' })
      .neq('kyc_status', 'not_submitted');

    if (status) query = query.eq('kyc_status', status);
    if (search) query = query.or(`users.first_name.ilike.%${search}%,users.last_name.ilike.%${search}%`);

    query = query.order('uploaded_at', { ascending: false, foreignTable: 'kyc_documents' }).range(offset, offset + limit - 1);

    const { data, error } = await query;
    if (error) return errorResponse('Failed to fetch KYC list', 500, 'SERVER_ERROR');

    // Flatten the lender_profile groups into ONE row per KYC document so the
    // list rows map cleanly to KycDocumentModel and each row's `id` is the real
    // kyc_documents.id (needed for the details screen + kyc-verify).
    const mapped = (data ?? []).flatMap((row: any) => {
      const docs = row.kyc_documents ?? [];
      if (docs.length === 0) {
        return [
          {
            id: null,
            lender_id: row.id,
            document_type: 'other',
            file_url: null,
            status: row.kyc_status ?? 'pending',
            created_at: row.updated_at ?? row.created_at ?? new Date().toISOString(),
            lender: row.users ?? null,
          },
        ];
      }
      return docs.map((d: any) => ({
        id: d.id,
        lender_id: row.id,
        document_type: d.document_type,
        file_url: d.file_path,
        status: d.status ?? row.kyc_status ?? 'pending',
        created_at: d.uploaded_at,
        rejection_notes: d.rejection_notes ?? null,
        reviewed_by: d.reviewed_by ?? null,
        reviewed_at: d.reviewed_at ?? null,
        lender: row.users ?? null,
      }));
    }).filter((d: any) => d.id != null);

    return jsonResponse({ data: mapped, total: mapped.length, page, limit, totalPages: Math.ceil(mapped.length / limit) });
  } catch (err) {
    console.error('kyc-get-list error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});