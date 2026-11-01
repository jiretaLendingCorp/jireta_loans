// lib/core/validation/co_maker_document_rules.dart
//
// Limitasyon sa pag-upload ng Co-maker Valid ID (Front + Back) sa loan
// application: 5MB bawat side. Kapareho ito ng server-side guard sa
// `supabase/functions/loans-apply/index.ts` — kapag binago ang isa, baguhin
// din ang isa.
class CoMakerDocumentRules {
  CoMakerDocumentRules._();

  /// Bawat side ng Co-maker Valid ID: hanggang 5MB.
  static const int maxBytes = 5 * 1024 * 1024;

  /// Label para sa error message.
  static const String limitLabel = '5MB';

  /// Signature file (JPG/PNG) na ini-attach kapalit ng drawing: 5MB din.
  static const int signatureMaxBytes = 5 * 1024 * 1024;

  /// Null kapag pasado ang laki; error message kapag sobra o blangko.
  static String? validateSize({required String side, required int sizeBytes}) {
    if (sizeBytes <= 0) return 'The selected file is empty.';
    if (sizeBytes > maxBytes) {
      return '$side of the Co-maker Valid ID is too large — maximum size is '
          '$limitLabel.';
    }
    return null;
  }

  /// Null kapag pasado ang laki ng signature file; error message kapag sobra
  /// o blangko.
  static String? validateSignatureSize({required int sizeBytes}) {
    if (sizeBytes <= 0) return 'The selected file is empty.';
    if (sizeBytes > signatureMaxBytes) {
      return 'Signature file is too large — maximum size is $limitLabel.';
    }
    return null;
  }
}
