// supabase/functions/_shared/ci_docs.ts
//
// Patakaran sa CI evidence uploads — server-side. Kapareho ito ng
// `lib/core/validation/ci_evidence_rules.dart` (client guard); kapag binago ang
// limitasyon dito, baguhin din ang client copy.
//
// Layunin: tanggihan ang oversize na evidence BAGO pa ma-upload sa storage.
// Isang bigong photo lang ay nagpapabagsak sa buong submit (batch ang upload),
// at ang base64 JSON na pinapadala ng rider app ay mabilis lumaki.

/** 5MB kada evidence photo ng CI. */
export const MAX_CI_EVIDENCE_BYTES = 5 * 1024 * 1024;

/** Label para sa error message. */
export const CI_EVIDENCE_LIMIT_LABEL = "5MB";

/**
 * Null kapag tama ang laki; error message kapag blangko o lumampas sa 5MB.
 *
 * [byteLength] ang na-decode na laki (hindi ang base64 string), kaya tugma ito
 * sa aktwal na file na ise-save sa storage bucket.
 */
export function validateCiEvidenceSize(
  fileName: string | null | undefined,
  byteLength: number,
): string | null {
  const label = (fileName ?? "").trim() || "Evidence photo";
  if (!Number.isFinite(byteLength) || byteLength <= 0) {
    return `${label} is empty`;
  }
  if (byteLength > MAX_CI_EVIDENCE_BYTES) {
    return `${label} is too large — maximum is ${CI_EVIDENCE_LIMIT_LABEL} per photo`;
  }
  return null;
}
