
// supabase/functions/collections-upload-proof/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;
    const roleCheck = requireRole(user, ROLES.RIDER);
    if (roleCheck) return roleCheck;
    const { assignment_id, proof_photo_url, borrower_signature_url, collection_photo_url, latitude, longitude } = await req.json();
    if (!assignment_id || !proof_photo_url) return errorResponse('assignment_id and proof_photo_url required', 400, 'VALIDATION_ERROR');
    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
    const { data: assignment } = await db.from('collection_assignments').select('id, status, rider_id').eq('id', assignment_id).eq('rider_id', user.id).single();
    if (!assignment) return errorResponse('Assignment not found', 404, 'NOT_FOUND');
    if (!['accepted', 'in_progress'].includes(assignment.status)) return errorResponse('Invalid assignment status', 400, 'INVALID_STATUS');
    await db.from('collection_assignments').update({
      proof_photo_url,
      borrower_signature_url: borrower_signature_url ?? null,
      collection_photo_url: collection_photo_url ?? null,
      proof_latitude: latitude ?? null,
      proof_longitude: longitude ?? null,
      status: 'completed',
      completed_at: new Date().toISOString(),
    }).eq('id', assignment_id);
    await writeAuditLog({ performedBy: user.id, action: 'collection_upload_proof', tableName: 'collection_assignments', recordId: assignment_id, ipAddress: ip });
    return jsonResponse({ message: 'Proof uploaded, assignment completed' });
  } catch (err) {
    console.error('collections-upload-proof error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});