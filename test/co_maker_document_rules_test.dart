// test/co_maker_document_rules_test.dart
//
// Client-side guard ng Co-maker Valid ID (Front + Back): 5MB bawat side.
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/validation/co_maker_document_rules.dart';

const _mb = 1024 * 1024;

void main() {
  group('Co-maker Valid ID size', () {
    test('5MB ang limit bawat side', () {
      expect(CoMakerDocumentRules.maxBytes, 5 * _mb);
      expect(CoMakerDocumentRules.limitLabel, '5MB');
    });

    test('tumatanggap ng 5MB pero tinatanggihan ang sobra', () {
      expect(
        CoMakerDocumentRules.validateSize(side: 'Front', sizeBytes: 5 * _mb),
        isNull,
      );
      final tooBig = CoMakerDocumentRules.validateSize(
        side: 'Back',
        sizeBytes: 5 * _mb + 1,
      );
      expect(tooBig, isNotNull);
      expect(tooBig, contains('5MB'));
    });

    test('signature file ay 5MB din ang limit', () {
      expect(
        CoMakerDocumentRules.validateSignatureSize(sizeBytes: 5 * _mb),
        isNull,
      );
      final tooBig = CoMakerDocumentRules.validateSignatureSize(
        sizeBytes: 5 * _mb + 1,
      );
      expect(tooBig, isNotNull);
      expect(tooBig, contains('5MB'));
    });

    test('blangkong file ay tinatanggihan', () {
      expect(
        CoMakerDocumentRules.validateSize(side: 'Front', sizeBytes: 0),
        isNotNull,
      );
    });
  });
}
