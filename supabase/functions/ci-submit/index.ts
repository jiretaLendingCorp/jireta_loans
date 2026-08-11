// supabase/functions/ci-submit/index.ts
// ─────────────────────────────────────────────────────────────────────────────
// MERGED EDGE FUNCTION — routes multiple actions through ONE deployable
// function using the `?fn=<action>` query parameter.
//
//   ci-submit-report     →  ?fn=submit-report
//   ci-upload-documents  →  ?fn=upload-documents
//
// The original per-action logic is preserved verbatim below; each handler is
// only wrapped so it can live in a single `serve()`.
// ─────────────────────────────────────────────────────────────────────────────
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeString } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { notifyStaff } from '../_shared/notifications.ts';

// ── [moved from ci-upload-documents] ────────────────────────────────────────
const BUCKET = 'ci-documents';

// ── [moved from ci-upload-documents] ────────────────────────────────────────
// Decode a base64 string into a Uint8Array without relying on atob.
function base64ToBytes(base64: string): Uint8Array {
  const bin = atob(base64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

// ── [moved from ci-upload-documents] ────────────────────────────────────────
function mimeFromExt(ext: string): string {
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'pdf':
      return 'application/pdf';
    default:
      return 'application/octet-stream';
  }
}

// ══ ROUTER ══════════════════════════════════════════════════════════════════
const DEFAULT_ACTION = 'submit-report';

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const fn = new URL(req.url).searchParams.get('fn') ?? DEFAULT_ACTION;
    switch (fn) {
      case 'submit-report':
        // ── [moved from functions/ci-submit-report/index.ts] ─────────────
        return await handleCiSubmitReport(req);
      case 'upload-documents':
        // ── [moved from functions/ci-upload-documents/index.ts] ──────────
        return await handleCiUploadDocuments(req);
      default:
        return errorResponse(`Unknown action: ${fn}`, 404, 'NOT_FOUND');
    }
  } catch (err) {
    console.error('ci-submit error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});

// ── [moved from functions/ci-submit-report/index.ts] ────────────────────────
async function handleCiSubmitReport(req: Request) {
  const authResult = await requireAuth(req);
  if (!isAuthUser(authResult)) return authResult;
  const user = authResult;
  const roleCheck = requireRole(user, ROLES.RIDER);
  if (roleCheck) return roleCheck;
  const { ci_id, report_summary } = await req.json();
  if (!ci_id || !report_summary) return errorResponse('ci_id and report_summary are required', 400, 'VALIDATION_ERROR');
  const db = getAdminClient();
  const ip = req.headers.get('x-forwarded-for') ?? 'unknown';
  const { data: ci } = await db.from('credit_investigations').select('id, status, rider_id, loan_id').eq('id', ci_id).eq('rider_id', user.id).single();
  if (!ci) return errorResponse('CI not found', 404, 'NOT_FOUND');
  if (!['accepted', 'in_progress'].includes(ci.status)) return errorResponse('CI is not in progress', 400, 'INVALID_STATUS');
  const { count: docCount } = await db.from('ci_documents').select('*', { count: 'exact', head: true }).eq('ci_id', ci_id);
  if ((docCount ?? 0) === 0) return errorResponse('At least 1 document must be uploaded', 400, 'VALIDATION_ERROR');
  await db.from('credit_investigations').update({ status: 'completed', report_summary: sanitizeString(report_summary), completed_at: new Date().toISOString() }).eq('id', ci_id);
  await db.from('loans').update({ status: 'ci_completed' }).eq('id', ci.loan_id);
  await db.from('rider_profiles').update({ is_available: true }).eq('id', user.id);
  await writeAuditLog({ performedBy: user.id, action: 'ci_submit_report', tableName: 'credit_investigations', recordId: ci_id, ipAddress: ip });
  await notifyStaff({ title: 'CI Report Submitted', body: 'A rider has submitted a credit investigation report. Ready for approval.', type: 'ci_completed', referenceId: ci.loan_id });
  return jsonResponse({ message: 'CI report submitted. Loan is ready for approval.' });
}

// ── [moved from functions/ci-upload-documents/index.ts] ─────────────────────
async function handleCiUploadDocuments(req: Request) {
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

  const docsToInsert = [];
  for (let i = 0; i < documents.length; i++) {
    const d = documents[i];
    const ext = (d.file_name ?? 'document').split('.').pop()?.toLowerCase() ?? 'jpg';
    const safeExt = ['jpg', 'jpeg', 'png', 'webp', 'pdf'].includes(ext) ? ext : 'jpg';
    const objectPath = `ci/${ci_id}/${crypto.randomUUID()}.${safeExt}`;

    // The rider client sends content_base64 (no file_url). Mirror kyc-submit:
    // upload to storage and keep the object path, never the raw base64.
    let storedPath = d.file_url ?? null;
    if (d.content_base64) {
      const { error: uploadErr } = await db.storage
        .from(BUCKET)
        .upload(objectPath, base64ToBytes(d.content_base64), {
          contentType: d.mime_type ?? mimeFromExt(safeExt),
          upsert: false,
        });
      if (uploadErr) {
        return errorResponse(`Failed to upload document (${d.document_type ?? 'ci_photo'}): ${uploadErr.message}`, 500, 'STORAGE_ERROR');
      }
      storedPath = objectPath;
    }

    if (!storedPath) {
      return errorResponse('Each document must include content_base64 to store', 400, 'VALIDATION_ERROR');
    }

    docsToInsert.push({
      ci_id,
      file_path: storedPath,
      document_type: d.document_type ?? 'site_photo',
      file_name: d.file_name ?? 'ci_document',
      mime_type: d.mime_type ?? 'image/jpeg',
      notes: d.caption ?? null,
      latitude: d.latitude ?? null,
      longitude: d.longitude ?? null,
    });
  }
  await db.from('ci_documents').insert(docsToInsert);
  await writeAuditLog({ performedBy: user.id, action: 'ci_upload_documents', tableName: 'ci_documents', recordId: ci_id, ipAddress: ip });
  return jsonResponse({ message: 'Documents uploaded', count: docsToInsert.length }, 201);
}