// test/in_office_required_docs_test.dart
//
// REQUIRED NA DOKUMENTO SA LENDER ACCOUNT UPGRADE (walk-in)
//
// GINUSTO: **Valid ID (front + back) lang ang required** — hindi na dapat
// harangin ng Selfie with ID at Mayor's Permit ang Submit/Next (opsyonal na
// lang ang mga ito).
//
// BUG NA NAAYOS: may **UI/backend mismatch**. Ang wizard ay Valid ID lang ang
// hiningi, pero ang `in-office-view?fn=submit-account` ay nag-e-enforce pa rin
// ng limang dokumento → ang step-3 Submit ay pumapalya nang generic na
// "Account submit failed. Please try again." (INCOMPLETE_WIZARD 400).
// Ang dalawang panig ay dapat pareho ang listahan.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/features/head_manager/in_office/widgets/in_office_wizard.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('UI: kInOfficeRequiredDocTypes', () {
    test('Valid ID (front + back) lang ang required', () {
      expect(kInOfficeRequiredDocTypes, {'valid_id', 'valid_id_back'});
    });

    test('opsyonal ang selfie / mayor\'s permit', () {
      for (final type in const [
        'selfie',
        'mayors_permit',
      ]) {
        expect(kInOfficeRequiredDocTypes.contains(type), isFalse,
            reason: '$type ay hindi na dapat required');
      }
    });
  });

  group('Backend: in-office-view?fn=submit-account', () {
    late final String src = _read(
        'supabase/functions/in-office-view/index.ts');

    test('hindi na hino-hold ang submit sa selfie / permit', () {
      for (final type in const [
        "'selfie'",
        "'mayors_permit'",
      ]) {
        expect(
          src.contains(RegExp(
              r'STEP3_REQUIRED_DOCS\s*=\s*new Set\(\[[^\]]*' +
                  type +
                  r'[^\]]*\]',
              dotAll: true)),
          isFalse,
          reason:
              '$type ay hindi dapat kabilang sa STEP3_REQUIRED_DOCS — haharang '
              'ito sa step-3 Submit kahit Valid ID lang ang kailangan ng UI',
        );
      }
    });

    test('valid_id at valid_id_back pa rin ang required', () {
      final match = RegExp(r'STEP3_REQUIRED_DOCS\s*=\s*new Set\(\[([^\]]*)\]',
              dotAll: true)
          .firstMatch(src);
      expect(match, isNotNull, reason: 'dapat may STEP3_REQUIRED_DOCS');
      final set = match!.group(1)!;
      expect(set.contains("'valid_id'"), isTrue);
      expect(set.contains("'valid_id_back'"), isTrue);
    });
  });
}
