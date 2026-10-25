// test/delivery_proof_rules_test.dart
//
// Client-side guard ng Cash on Delivery proof upload: 5MB TOTAL para sa buong
// upload (hindi kada photo) at image files lang. Ang upload endpoint ay base64
// JSON (hanggang 2 photos + signature sa isang request), kaya kapag lumampas
// ang kabuuan ay nagpapabagsak ito sa buong submit — kaya hinaharang na bago
// umabot sa server.
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/validation/delivery_proof_rules.dart';

const _mb = 1024 * 1024;

void main() {
  test('5MB total ang limit ng upload', () {
    expect(DeliveryProofRules.maxBytes, 5 * _mb);
    expect(DeliveryProofRules.maxLabel, '5MB');
  });

  test('tumatanggap ng hanggang 5MB total, tinatanggihan ang lumampas', () {
    // Dalawang 2.5MB na photo = 5MB total — pasado pa rin.
    expect(DeliveryProofRules.isWithinLimit((2.5 * _mb).round() * 2), isTrue);
    expect(DeliveryProofRules.isWithinLimit(5 * _mb), isTrue);
    expect(DeliveryProofRules.isWithinLimit(5 * _mb + 1), isFalse);
  });

  test('image lang ang tinatanggap', () {
    expect(DeliveryProofRules.isImage('image/jpeg'), isTrue);
    expect(DeliveryProofRules.isImage('image/png'), isTrue);
    expect(DeliveryProofRules.isImage('image/webp'), isTrue);
    expect(DeliveryProofRules.isImage(null), isTrue);
    expect(DeliveryProofRules.isImage(''), isTrue);
    expect(DeliveryProofRules.isImage('application/pdf'), isFalse);
  });

  test('makikita sa error message ang kabuuang laki', () {
    expect(DeliveryProofRules.sizeLabel(5 * _mb), '5.0 MB');
    expect(DeliveryProofRules.sizeLabel(820 * 1024), '820 KB');

    final msg = DeliveryProofRules.oversizeMessage(7 * _mb);
    expect(msg, contains('7.0 MB'));
    expect(msg, contains('total'));
    expect(msg, contains('5MB'));
  });
}
