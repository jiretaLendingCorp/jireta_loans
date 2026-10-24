// lib/core/validation/ci_evidence_rules.dart
//
// Panuntunan sa pag-upload ng CI evidence. May 5MB na limit kada photo ang
// upload endpoint (base64 JSON ang pinapadala, kaya mabilis lumaki ang
// request), at kapag lumampas ang isang photo ay bigo ang buong submit. Kaya
// hinaharang na ito sa client bago pa umabot sa server.
//
// Ang server-side check ay nasa `supabase/functions/_shared/ci_docs.ts` — kapag
// binago ang limitasyon dito, baguhin din ang server copy (at vice versa).
class CiEvidenceRules {
  CiEvidenceRules._();

  /// 5MB kada evidence photo — tugma sa limit ng backend.
  static const int maxBytes = 5 * 1024 * 1024;

  /// Label para sa UI at error messages.
  static const String maxLabel = '5MB';

  static bool isWithinLimit(int sizeBytes) => sizeBytes <= maxBytes;

  /// `2.4 MB` / `820 KB` — size label ng bawat piniling photo.
  static String sizeLabel(int sizeBytes) {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / 1024).ceil()} KB';
  }

  /// Mensahe para sa mga piniling photo na lumampas sa limit. Nananatili sa
  /// listahan ang mga ito (para makita ng rider kung alin) pero hindi puwedeng
  /// i-submit hangga't hindi nare-remove o napalitan ng mas maliit na photo.
  /// Kapag isa lang, isinasama ang aktwal na laki.
  static String rejectedMessage(int rejectedCount, {int? largestBytes}) {
    if (rejectedCount == 1 && largestBytes != null) {
      return 'Photo is ${sizeLabel(largestBytes)} — over the $maxLabel limit. '
          'Remove it or choose a smaller one.';
    }
    if (rejectedCount == 1) {
      return 'Photo is over the $maxLabel limit. '
          'Remove it or choose a smaller one.';
    }
    return '$rejectedCount photos are over the $maxLabel limit. '
        'Remove them or choose smaller ones.';
  }
}
