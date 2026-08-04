// supabase/functions/collections-upload-proof/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { writeAuditLog } from '../_shared/audit.ts';

const BUCKET = 'collection-proofs';

const COLUMN_BY_TYPE: Record<string, string> = {
  proof_photo: 'proof_photo',
  scene_photo: 'collection_photo',
  signature: 'borrower_signature',
};

function decodeBase64(content: string): Uint8Array {
  const binary = atob(content);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function extFromMime(mimeType?: string): string {
  switch ((mimeType ?? '').toLowerCase()) {
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    case 'image/gif':
      return 'gif';
    case 'image/bmp':
      return 'bmp';
    default:
      return 'jpg';
  }
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;
  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;
    const roleCheck = requireRole(user, ROLES.RIDER);
    if (roleCheck) return roleCheck;

    const { assignment_id, proofs } = await req.json();
    if (!assignment_id || !Array.isArray(proofs) || proofs.length === 0) {
      return errorResponse('assignment_id and proofs[] required', 400, 'VALIDATION_ERROR');
    }
    if (!proofs.some((p) => p?.type === 'proof_photo')) {
      return errorResponse('At least one proof_photo is required', 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    const { data: assignment } = await db
      .from('collection_assignments')
      .select('id, status, rider_id, proof_photo, borrower_signature, collection_photo')
      .eq('id', assignment_id)
      .eq('rider_id', user.id)
      .single();
    if (!assignment) return errorResponse('Assignment not found', 404, 'NOT_FOUND');
    if (!['accepted', 'in_progress'].includes(assignment.status)) {
      return errorResponse('Invalid assignment status', 400, 'INVALID_STATUS');
    }

    const updates: Record<string, string> = {};
    for (const proof of proofs) {
      const type = proof?.type as string;
      const column = COLUMN_BY_TYPE[type];
      if (!column || !proof.content_base64) continue;

      const ext = extFromMime(proof.mime_type);
      const path = `${assignment_id}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
      const bytes = decodeBase64(proof.content_base64);

      const { error: uploadError } = await db.storage
        .from(BUCKET)
        .upload(path, bytes, { contentType: proof.mime_type ?? 'image/jpeg', upsert: true });

      if (uploadError) {
        console.warn('storage upload failed, falling back to data uri:', uploadError.message);
        const mime = proof.mime_type ?? 'image/jpeg';
        updates[column] = `data:${mime};base64,${proof.content_base64}`;
      } else {
        const { data: signedUrl } = await db.storage.from(BUCKET).createSignedUrl(path, 3600 * 24 * 7);
        updates[column] = (signedUrl as any)?.signedUrl ?? path;
      }
    }

    if (Object.keys(updates).length === 0) {
      return errorResponse('No valid proofs provided', 400, 'VALIDATION_ERROR');
    }

    await db.from('collection_assignments').update({
      ...updates,
      status: 'completed',
      completed_at: new Date().toISOString(),
    }).eq('id', assignment_id);

    await writeAuditLog({
      performedBy: user.id,
      action: 'collection_upload_proof',
      tableName: 'collection_assignments',
      recordId: assignment_id,
      newValues: { status: 'completed' },
      ipAddress: ip,
    });

    return jsonResponse({ message: 'Proof uploaded, assignment completed' });
  } catch (err) {
    console.error('collections-upload-proof error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});