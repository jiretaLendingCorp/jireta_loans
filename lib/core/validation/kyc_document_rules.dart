// lib/core/validation/kyc_document_rules.dart
//
// Mga patakaran sa pag-upload ng Account Upgrade documents. Ginagamit ito ng
// lender submit screen PARA HINDI na umabot sa server ang sobra ang laki o
// maling uri ng file. Kapareho ito ng limitasyon sa `kyc-submit` function
// (`supabase/functions/_shared/kyc_docs.ts`) — kapag binago ang isa, baguhin
// din ang isa.
class KycDocumentRules {
  KycDocumentRules._();

  /// Bawat side ng Valid Government ID: hanggang 10MB.
  static const int validIdMaxBytes = 10 * 1024 * 1024;

  /// Ang ibang dokumento (selfie, business permit, face recognition): 5MB.
  static const int defaultMaxBytes = 5 * 1024 * 1024;

  static const Set<String> allowedExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'pdf',
  };

  /// `valid_id` (front) at `valid_id_back` ang 10MB; lahat ng iba 5MB.
  static int maxBytesFor(String documentType) =>
      documentType == 'valid_id' || documentType == 'valid_id_back'
          ? validIdMaxBytes
          : defaultMaxBytes;

  /// Halimbawang label: `10MB` / `5MB` — para sa error message.
  static String limitLabelFor(String documentType) =>
      '${maxBytesFor(documentType) ~/ (1024 * 1024)}MB';

  /// Null kapag valid ang file; error message kapag hindi.
  ///
  /// [fileName] lang ang sinusuri (hindi ang nilalaman) — sapat ito para sa
  /// client-side guard. Ang totoong size/type check ay nasa server pa rin.
  static String? validate({
    required String documentType,
    required String fileName,
    required int sizeBytes,
  }) {
    if (sizeBytes <= 0) return 'The selected file is empty.';
    final maxBytes = maxBytesFor(documentType);
    if (sizeBytes > maxBytes) {
      return 'File is too large. Maximum size is ${maxBytes ~/ (1024 * 1024)}MB.';
    }
    final ext = fileName.split('.').last.toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      return 'Unsupported file type. Use JPG, PNG, WEBP, or PDF.';
    }
    return null;
  }
}
