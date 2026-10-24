// test/ci_evidence_rules_test.dart
//
// Client-side guard ng CI evidence upload: 5MB kada photo. Ang upload endpoint
// ay base64 JSON, kaya isang photo na lumampas sa limit ay nagpapabagsak sa
// buong submit — kaya hinaharang na ito bago umabot sa server.
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/validation/ci_evidence_rules.dart';

const _mb = 1024 * 1024;

void main() {
  test('5MB ang limit kada photo', () {
    expect(CiEvidenceRules.maxBytes, 5 * _mb);
    expect(CiEvidenceRules.maxLabel, '5MB');
  });

  test('tumatanggap ng hanggang 5MB, tinatanggihan ang lumampas', () {
    expect(CiEvidenceRules.isWithinLimit(5 * _mb), isTrue);
    expect(CiEvidenceRules.isWithinLimit(5 * _mb + 1), isFalse);
    expect(CiEvidenceRules.isWithinLimit(2 * _mb), isTrue);
  });

  test('size label ng bawat photo', () {
    expect(CiEvidenceRules.sizeLabel(2 * _mb + 512 * 1024), '2.5 MB');
    expect(CiEvidenceRules.sizeLabel(5 * _mb), '5.0 MB');
    expect(CiEvidenceRules.sizeLabel(820 * 1024), '820 KB');
  });

  test('malinaw ang mensahe; naka-flag pero hindi tinatago ang photo', () {
    expect(CiEvidenceRules.rejectedMessage(1), contains('5MB'));
    expect(CiEvidenceRules.rejectedMessage(1), contains('smaller'));
    expect(CiEvidenceRules.rejectedMessage(1), contains('Remove'));
    expect(CiEvidenceRules.rejectedMessage(3), contains('3 photos'));
    expect(CiEvidenceRules.rejectedMessage(3), contains('Remove them'));
  });

  test('isinasama ang aktwal na laki ng tinanggihang photo', () {
    final msg = CiEvidenceRules.rejectedMessage(
      1,
      largestBytes: 6 * _mb + 800 * 1024,
    );
    expect(msg, contains('6.8 MB'));
    expect(msg, contains('5MB'));
  });
}
