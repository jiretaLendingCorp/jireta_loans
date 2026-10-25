// lib/core/validation/delivery_proof_rules.dart
//
// Panuntunan sa pag-upload ng Cash on Delivery proof (rider → lender).
// Base64 JSON ang pinapadala sa `disbursements-manage?fn=upload-proof`, kaya
// mabilis lumaki ang request at bigo ang buong submit kapag lumampas ang
// payload. Hinaharang sa client bago pa umabot sa server.
//
// LIMIT: 5MB TOTAL para sa buong upload (lahat ng photos na pinili), hindi
// 5MB kada photo.
class DeliveryProofRules {
  DeliveryProofRules._();

  /// 5MB TOTAL para sa lahat ng proof photos ng isang submit.
  static const int maxBytes = 5 * 1024 * 1024;

  /// Label para sa UI at error messages.
  static const String maxLabel = '5MB';

  /// [totalBytes] ang pinagsamang laki ng lahat ng piniling photo.
  static bool isWithinLimit(int totalBytes) => totalBytes <= maxBytes;

  /// Image lang ang tinatanggap (JPG/PNG/WEBP/HEIC). Ang `null` mime ay
  /// pinapayagan — galing iyon sa camera/gallery picker na image lang ang
  /// ibinabalik.
  static bool isImage(String? mimeType) {
    final mime = mimeType?.toLowerCase().trim();
    if (mime == null || mime.isEmpty) return true;
    return mime.startsWith('image/');
  }

  /// `2.4 MB` / `820 KB` — size label para sa error message.
  static String sizeLabel(int sizeBytes) => sizeBytes >= 1024 * 1024
      ? '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(sizeBytes / 1024).ceil()} KB';

  static const String notImageMessage =
      'Only image files (JPG, PNG, WEBP) are allowed for Cash on Delivery proof.';

  /// Isinasama ang kabuuang laki para malinaw kung bakit tinanggihan.
  static String oversizeMessage(int totalBytes) =>
      'Photos are ${sizeLabel(totalBytes)} in total — over the $maxLabel limit. '
      'Remove one or choose smaller photos.';
}
