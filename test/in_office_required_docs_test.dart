// test/in_office_required_docs_test.dart
//
// REQUIRED NA DOKUMENTO SA LENDER ACCOUNT UPGRADE (walk-in)
//
// GINUSTO: **LAHAT ng dokumento ay required** — Valid ID (front + back,
// iisang Upload flow sa UI), Selfie with ID, Face Recognition, at Business
// Permit. Max 5MB bawat file.
//
// BUG NA NAAYOS: may **UI/backend mismatch**. Dati Valid ID lang ang hiningi
// ng wizard pero iba ang listahan ng `in-office-view?fn=submit-account`, kaya
// pumapalya ang step-3 Submit nang generic na
// "Account submit failed. Please try again." (INCOMPLETE_WIZARD 400).
// Ang dalawang panig ay dapat pareho ang listahan.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/features/head_manager/in_office/widgets/in_office_wizard.dart';

String _read(String path) => File(path).readAsStringSync();

const _allDocs = [
  'valid_id',
  'valid_id_back',
  'selfie',
  'face_recognition',
  'mayors_permit',
];

void main() {
  group('UI: kInOfficeRequiredDocTypes', () {
    test('lahat ng dokumento ay required', () {
      expect(kInOfficeRequiredDocTypes, _allDocs.toSet());
    });
  });

  group('Backend: in-office-view?fn=submit-account', () {
    late final String src =
        _read('supabase/functions/in-office-view/index.ts');

    test('lahat ng doc types ay nasa STEP3_REQUIRED_DOCS', () {
      final match = RegExp(
              r'STEP3_REQUIRED_DOCS\s*=\s*new Set\(\[([^\]]*)\]',
              dotAll: true)
          .firstMatch(src);
      expect(match, isNotNull, reason: 'dapat may STEP3_REQUIRED_DOCS');
      final set = match!.group(1)!;
      for (final type in _allDocs) {
        expect(set.contains("'$type'"), isTrue,
            reason: '$type ay dapat required sa step-3 Submit');
      }
    });
  });
}
