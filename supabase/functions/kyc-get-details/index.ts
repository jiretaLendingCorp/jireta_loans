// supabase/functions/kyc-get-details/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';

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
    if (!kycDocId) {
      return errorResponse('kyc_doc_id is required', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();

    const { data: raw, error } = await db
      .from('kyc_documents')
      .select(`
        id, lender_id, document_type, file_path, file_name, status,
        rejection_notes, reviewed_by, reviewed_at, uploaded_at
      `)
      .eq('id', kycDocId)
      .single();
    if (error || !raw) {
      return errorResponse('KYC document not found', 404, 'NOT_FOUND');
    }

    // lender_id points at lender_profiles.id which equals the users.id PK.
    const { data: userRow } = await db
      .from('users')
      .select('id, first_name, last_name, phone_number, email, account_status')
      .eq('id', (raw as any).lender_id)
      .single();

    const document = {
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
      lender: {
        id: (userRow as any)?.id ?? (raw as any).lender_id,
        first_name: (userRow as any)?.first_name,
        last_name: (userRow as any)?.last_name,
        phone_number: (userRow as any)?.phone_number,
        email: (userRow as any)?.email,
        account_status: (userRow as any)?.account_status,
      },
    };

    return jsonResponse({ document });
  } catch (err) {
    console.error('kyc-get-details error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});