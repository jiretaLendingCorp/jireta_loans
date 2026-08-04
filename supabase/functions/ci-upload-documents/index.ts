
// supabase/functions/ci-upload-documents/index.ts
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
    const { ci_id, documents } = await req.json();
    if (!ci_id || !documents || !Array.isArray(documents) || documents.length === 0) {
      return errorResponse('ci_id and documents[] are required', 400, 'VALIDATION_ERROR');
    }
    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
    const { data: ci } = await db.from('credit_investigations').select('id, status, rider_id').eq('id', ci_id).eq('rider_id', user.id).single();
    if (!ci) return errorResponse('CI not found', 404, 'NOT_FOUND');
    if (!['accepted', 'in_progress'].includes(ci.status)) return errorResponse('CI must be accepted first', 400, 'INVALID_STATUS');

    await db.from('credit_investigations').update({ status: 'in_progress' }).eq('id', ci_id);

    const docsToInsert = documents.map((d: any) => ({
      ci_id,
      file_path: d.file_url,
      document_type: d.document_type ?? 'site_photo',
      file_name: d.file_name ?? 'ci_document',
      mime_type: d.mime_type ?? 'application/octet-stream',
      notes: d.caption ?? null,
      latitude: d.latitude ?? null,
      longitude: d.longitude ?? null,
    }));
    await db.from('ci_documents').insert(docsToInsert);
    await writeAuditLog({ performedBy: user.id, action: 'ci_upload_documents', tableName: 'ci_documents', recordId: ci_id, ipAddress: ip });
    return jsonResponse({ message: 'Documents uploaded', count: docsToInsert.length }, 201);
  } catch (err) {
    console.error('ci-upload-documents error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});