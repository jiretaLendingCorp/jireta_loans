
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

    const roleCheck = requireRole(user, ROLES.LENDER);
    if (roleCheck) return roleCheck;

    const db = getAdminClient();
    const { data: profile } = await db.from('lender_profiles').select('kyc_status').eq('user_id', user.id).single();
    const { data: docs } = await db.from('kyc_documents').select('id, document_type, file_url, status, rejection_notes, created_at, verified_at').eq('user_id', user.id).order('created_at', { ascending: false });

    return jsonResponse({ kyc_status: profile?.kyc_status ?? 'not_submitted', documents: docs ?? [] });
  } catch (err) {
    console.error('kyc-get-status error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});