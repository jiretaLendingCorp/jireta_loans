// supabase/functions/_shared/kyc_docs.ts
//
// Patakaran sa Account Upgrade document uploads — server-side. Kapareho ito ng
// `lib/core/validation/kyc_document_rules.dart` (client guard); kapag binago
// ang limitasyon dito, baguhin din ang client copy.
//
// Layunin: tanggihan ang oversize / maling uri / kulang na dokumento BAGO pa
// ma-upload sa storage, para hindi mapuno ang bucket at hindi mabigat ang
// base64 payload sa Edge Function.

/** Bawat side ng Valid Government ID: 10MB. */
export const MAX_VALID_ID_BYTES = 10 * 1024 * 1024;

/** Lahat ng ibang dokumento (selfie, business permit, face recognition): 5MB. */
export const MAX_DOCUMENT_BYTES = 5 * 1024 * 1024;

/** Valid ID (front) at ang back side nito. */
export const VALID_ID_DOC_TYPES = ["valid_id", "valid_id_back"] as const;

/**
 * Kailangan bago maging kumpleto ang Account Upgrade submit — kasama ang
 * Valid Government ID (front + back).
 */
export const REQUIRED_ACCOUNT_UPGRADE_DOCS = [
  "valid_id",
  "valid_id_back",
  "selfie",
  "mayors_permit",
  "face_recognition",
] as const;

/** Isang submit lang dapat ang isang lender — sobra sa bilang = kalabisan. */
export const MAX_DOCUMENTS_PER_SUBMIT = 10;

export const ALLOWED_DOC_EXTENSIONS = [
  "jpg",
  "jpeg",
  "png",
  "webp",
  "pdf",
] as const;

export const ALLOWED_DOC_MIMES = [
  "image/jpeg",
  "image/png",
  "image/webp",
  "application/pdf",
] as const;

export function maxBytesForDocumentType(documentType: string): number {
  return (VALID_ID_DOC_TYPES as readonly string[]).includes(documentType)
    ? MAX_VALID_ID_BYTES
    : MAX_DOCUMENT_BYTES;
}

export function extensionOf(fileName: string | null | undefined): string {
  const name = (fileName ?? "").trim().toLowerCase();
  const dot = name.lastIndexOf(".");
  if (dot < 0 || dot === name.length - 1) return "";
  return name.substring(dot + 1);
}

export function isAllowedExtension(ext: string): boolean {
  return (ALLOWED_DOC_EXTENSIONS as readonly string[]).includes(ext);
}

export function isAllowedMime(mime: string): boolean {
  return (ALLOWED_DOC_MIMES as readonly string[]).includes(
    mime.trim().toLowerCase(),
  );
}

/** Null kapag tama ang laki; error message kapag hindi. */
export function validateDocumentSize(
  documentType: string,
  byteLength: number,
): string | null {
  if (!Number.isFinite(byteLength) || byteLength <= 0) {
    return `Document (${documentType}) is empty`;
  }
  const maxBytes = maxBytesForDocumentType(documentType);
  if (byteLength > maxBytes) {
    return `Document (${documentType}) is too large — maximum is ${
      maxBytes / (1024 * 1024)
    }MB`;
  }
  return null;
}

/** Filename extension at (kung ibinigay) mime type. */
export function validateDocumentMeta(doc: {
  document_type: string;
  file_name?: string | null;
  mime_type?: string | null;
}): string | null {
  const ext = extensionOf(doc.file_name);
  const hasFileName = !!doc.file_name && doc.file_name.trim() !== "";
  if (hasFileName && !isAllowedExtension(ext)) {
    return `Unsupported file type for ${doc.document_type} — use JPG, PNG, WEBP, or PDF`;
  }
  if (doc.mime_type && !isAllowedMime(doc.mime_type)) {
    return `Unsupported MIME type for ${doc.document_type}: ${doc.mime_type}`;
  }
  return null;
}

/**
 * Buong set ng dokumento: bilang, duplicates, at required types. Null kapag
 * pasado.
 */
export function validateDocumentSet(documentTypes: string[]): string | null {
  if (!Array.isArray(documentTypes) || documentTypes.length === 0) {
    return "Documents are required";
  }
  if (documentTypes.length > MAX_DOCUMENTS_PER_SUBMIT) {
    return `Too many documents — maximum is ${MAX_DOCUMENTS_PER_SUBMIT}`;
  }

  const seen = new Set<string>();
  for (const type of documentTypes) {
    if (!type) return "Each document needs document_type";
    if (seen.has(type)) return `Duplicate document_type: ${type}`;
    seen.add(type);
  }

  const missing = REQUIRED_ACCOUNT_UPGRADE_DOCS.filter((t) => !seen.has(t));
  if (missing.length > 0) {
    return `Missing required document(s): ${missing.join(", ")}`;
  }
  return null;
}
