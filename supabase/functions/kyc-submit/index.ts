// supabase/functions/kyc-submit/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { handleCors, jsonResponse, errorResponse } from '../_shared/cors.ts';
import { requireAuth, isAuthUser } from '../_shared/auth.ts';
import { requireRole, ROLES } from '../_shared/rbac.ts';
import { getAdminClient } from '../_shared/db.ts';
import { sanitizeString, validatePhone } from '../_shared/validators.ts';
import { writeAuditLog } from '../_shared/audit.ts';
import { notifyStaff } from '../_shared/notifications.ts';

function normalizeEnum(value: string | undefined | null): string | null {
  if (!value) return null;
  return sanitizeString(value).trim().toLowerCase().replace(/\s+/g, '_');
}

const ALLOWED_TYPES = [
  'valid_id', 'selfie', 'proof_of_billing', 'proof_of_income',
  'barangay_clearance', 'pay_slip', 'certificate_of_employment',
  'itr', 'business_registration', 'co_maker', 'other',
];

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

// Decode a base64 string into a Uint8Array without relying on atob.
function base64ToBytes(base64: string): Uint8Array {
  const bin = atob(base64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

serve(async (req) => {
  const cors = handleCors(req);
  if (cors) return cors;

  try {
    const authResult = await requireAuth(req);
    if (!isAuthUser(authResult)) return authResult;
    const user = authResult;

    const roleCheck = requireRole(user, ROLES.LENDER);
    if (roleCheck) return roleCheck;

    const body = await req.json();
    const { documents, address_info, source_of_funds, emergency_contact } = body;

    if (!documents || !Array.isArray(documents) || documents.length === 0) {
      return errorResponse('At least one document is required', 400, 'VALIDATION_ERROR');
    }

    for (const doc of documents) {
      if (!doc.document_type) return errorResponse('Each document needs document_type', 400, 'VALIDATION_ERROR');
      if (!ALLOWED_TYPES.includes(doc.document_type)) return errorResponse(`Invalid document_type: ${doc.document_type}`, 400, 'VALIDATION_ERROR');
    }

    const db = getAdminClient();
    const ip = req.headers.get('x-forwarded-for') ?? 'unknown';

    // Upload each document to the kyc-documents storage bucket (service role)
    // and store the returned object path — NOT the raw base64 payload which
    // would overflow the VARCHAR(255) file_path column.
    const docsToInsert = [];
    for (let i = 0; i < documents.length; i++) {
      const doc = documents[i];
      const ext = (doc.file_name ?? 'document').split('.').pop()?.toLowerCase() ?? 'jpg';
      const safeExt = ['jpg', 'jpeg', 'png', 'webp', 'pdf'].includes(ext) ? ext : 'jpg';
      const objectPath = `kyc/${user.id}/${crypto.randomUUID()}.${safeExt}`;

      let storedPath = doc.file_url ?? null;
      if (doc.content_base64) {
        const { error: uploadErr } = await db.storage
          .from('kyc-documents')
          .upload(objectPath, base64ToBytes(doc.content_base64), {
            contentType: doc.mime_type ?? mimeFromExt(safeExt),
            upsert: false,
          });
        if (uploadErr) {
          return errorResponse(`Failed to upload document (${doc.document_type}): ${uploadErr.message}`, 500, 'STORAGE_ERROR');
        }
        storedPath = objectPath;
      }

      if (!storedPath) {
        return errorResponse(`Document (${doc.document_type}) has no content to store`, 400, 'VALIDATION_ERROR');
      }

      docsToInsert.push({
        lender_id: user.id,
        document_type: doc.document_type,
        file_path: storedPath,
        file_name: doc.file_name ?? 'document',
        file_size: doc.file_size ?? 1,
        mime_type: doc.mime_type ?? mimeFromExt(safeExt),
        status: 'pending',
      });
    }

    const { error: insertErr } = await db.from('kyc_documents').insert(docsToInsert);
    if (insertErr) return errorResponse(`Failed to save KYC documents: ${insertErr.message}`, 500, 'DB_ERROR');

    // Persist the residence / financial information the lender filled in.
    if (address_info || source_of_funds) {
      const ai = address_info ?? {};
      const { error: profileErr } = await db.from('lender_profiles').update({
        street_address: ai.street_address ? sanitizeString(ai.street_address) : undefined,
        barangay: ai.barangay ? sanitizeString(ai.barangay) : undefined,
        city: ai.city ? sanitizeString(ai.city) : undefined,
        province: ai.province ? sanitizeString(ai.province) : undefined,
        zip_code: ai.zip_code ? sanitizeString(ai.zip_code) : undefined,
        source_of_funds: source_of_funds ? normalizeEnum(source_of_funds) : undefined,
      }).eq('id', user.id);
      if (profileErr) console.error('kyc-submit profile update error:', profileErr.message);
    }

    // Emergency contact (one per lender is sufficient for KYC).
    if (emergency_contact?.name && emergency_contact?.phone_number) {
      const { error: ecErr } = await db.from('emergency_contacts').upsert({
        lender_id: user.id,
        name: sanitizeString(emergency_contact.name),
        relationship: sanitizeString(emergency_contact.relationship ?? 'Other'),
        phone_number: sanitizeString(emergency_contact.phone_number),
        address: emergency_contact.address ? sanitizeString(emergency_contact.address) : null,
      }, { onConflict: 'lender_id' }).select('id').single();
      if (ecErr) console.error('kyc-submit emergency contact error:', ecErr.message);
    }

    const { error: statusErr } = await db.from('lender_profiles').update({ kyc_status: 'submitted' }).eq('id', user.id);
    if (statusErr) return errorResponse('Failed to update KYC status', 500, 'DB_ERROR');

    await writeAuditLog({ performedBy: user.id, action: 'kyc_submit', tableName: 'kyc_documents', recordId: user.id, ipAddress: ip });
    await notifyStaff({ title: 'KYC Submitted', body: 'A lender has submitted KYC documents for review.', type: 'kyc_submitted', referenceId: user.id, sentBy: user.id });

    return jsonResponse({ message: 'KYC documents submitted successfully' }, 201);
  } catch (err) {
    console.error('kyc-submit error:', err);
    return errorResponse('Internal server error', 500, 'SERVER_ERROR');
  }
});
