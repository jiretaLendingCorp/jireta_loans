// supabase/functions/_shared/delivery_proof.ts
//
// Patakaran sa Cash on Delivery proof uploads — SERVER-SIDE. Kapareho ito ng
// `lib/core/validation/delivery_proof_rules.dart` (client guard); kapag binago
// ang limitasyon dito, baguhin din ang client copy.
//
// Layunin: tanggihan ang oversize na proof BAGO pa ma-upload sa storage.
// Base64 JSON ang pinapadala ng rider app (hanggang 2 photos + signature sa
// isang request), kaya mabilis lumaki ang payload at pwedeng lumampas sa limit
// ng Edge Function.
//
// LIMIT: 5MB TOTAL para sa buong upload — hindi 5MB kada file.

/** 5MB TOTAL para sa lahat ng proof files ng isang submit. */
export const MAX_DELIVERY_PROOF_BYTES = 5 * 1024 * 1024;

/** Label para sa error message. */
export const DELIVERY_PROOF_LIMIT_LABEL = "5MB";

function sizeLabel(byteLength: number): string {
  return byteLength >= 1024 * 1024
    ? `${(byteLength / (1024 * 1024)).toFixed(1)} MB`
    : `${Math.ceil(byteLength / 1024)} KB`;
}

/**
 * Null kapag pasok sa 5MB TOTAL; error message kapag blangko o lumampas.
 *
 * [byteLength] ang na-decode na laki ng LAHAT ng proof files (hindi ang base64
 * string), kaya tugma ito sa aktwal na ise-save sa storage bucket.
 */
export function validateDeliveryProofTotal(byteLength: number): string | null {
  if (!Number.isFinite(byteLength) || byteLength <= 0) {
    return "No valid proof files were uploaded";
  }
  if (byteLength > MAX_DELIVERY_PROOF_BYTES) {
    return `Proof files are ${sizeLabel(byteLength)} in total — maximum is ${DELIVERY_PROOF_LIMIT_LABEL} per upload`;
  }
  return null;
}
