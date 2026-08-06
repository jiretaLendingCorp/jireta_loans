// supabase/functions/kyc-get-status/index.ts
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

    const documents = (docs ?? []).map((d: any) => ({
      ...d,
      file_url: d.file_path,
      created_at: d.uploaded_at,
    }));

    return jsonResponse({
      kyc_status: profile?.kyc_status ?? 'not_submitted',
      lender_id: lenderId,
      lender: profile ?? null,
      documents,
      emergency_contacts: emergencyContacts ?? [],
    });
  } catch (err) {
    console.error('kyc-get-status error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
