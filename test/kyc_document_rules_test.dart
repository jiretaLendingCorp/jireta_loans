// test/kyc_document_rules_test.dart
//
// Client-side guard ng Account Upgrade uploads: 10MB bawat side ng Valid
// Government ID, 5MB ang ibang dokumento, at JPG/PNG/WEBP/PDF lang.
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/validation/kyc_document_rules.dart';

const _mb = 1024 * 1024;

void main() {
  group('laki ng file', () {
    test('Valid ID front at back ay 10MB', () {
      expect(KycDocumentRules.maxBytesFor('valid_id'), 10 * _mb);
      expect(KycDocumentRules.maxBytesFor('valid_id_back'), 10 * _mb);
      expect(KycDocumentRules.limitLabelFor('valid_id'), '10MB');
    });

    test('selfie, business permit, face recognition ay 5MB', () {
      for (final type in ['selfie', 'mayors_permit', 'face_recognition']) {
        expect(KycDocumentRules.maxBytesFor(type), 5 * _mb);
        expect(KycDocumentRules.limitLabelFor(type), '5MB');
      }
    });

    test('tumatanggap ng 10MB Valid ID pero tinatanggihan ang sobra', () {
      expect(
        KycDocumentRules.validate(
          documentType: 'valid_id',
          fileName: 'front.jpg',
          sizeBytes: 10 * _mb,
        ),
        isNull,
      );
      final tooBig = KycDocumentRules.validate(
        documentType: 'valid_id',
        fileName: 'front.jpg',
        sizeBytes: 10 * _mb + 1,
      );
      expect(tooBig, isNotNull);
      expect(tooBig, contains('10MB'));
    });

    test('5MB+ na selfie ay tinatanggihan', () {
      final tooBig = KycDocumentRules.validate(
        documentType: 'selfie',
        fileName: 'selfie.jpg',
        sizeBytes: 5 * _mb + 1,
      );
      expect(tooBig, isNotNull);
      expect(tooBig, contains('5MB'));
    });

    test('blangkong file ay tinatanggihan', () {
      expect(
        KycDocumentRules.validate(
          documentType: 'selfie',
          fileName: 'selfie.jpg',
          sizeBytes: 0,
        ),
        isNotNull,
      );
    });
  });

  group('uri ng file', () {
    test('tumatanggap ng jpg, jpeg, png, webp, pdf', () {
      for (final ext in ['jpg', 'jpeg', 'png', 'webp', 'pdf']) {
        expect(
          KycDocumentRules.validate(
            documentType: 'selfie',
            fileName: 'file.$ext',
            sizeBytes: 1024,
          ),
          isNull,
          reason: 'Dapat tanggapin ang .$ext',
        );
      }
    });

    test('tinatanggihan ang ibang extension kahit maliit ang file', () {
      final error = KycDocumentRules.validate(
        documentType: 'mayors_permit',
        fileName: 'permit.exe',
        sizeBytes: 1024,
      );
      expect(error, isNotNull);
      expect(error, contains('Unsupported'));
    });
  });
}
