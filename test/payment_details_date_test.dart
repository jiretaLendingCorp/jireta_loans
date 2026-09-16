// test/payment_details_date_test.dart
// Coverage para sa bug na "mali ang date" sa payment details / receipt:
//   ANG +8h SHIFT AY NAIDADAGDAG NANG DALAWA.
//
// Ang `PaymentModel.createdAt` ay Manila wall time na (dumaan sa `parseManila`).
// Kapag ni-encode pa ito pabalik sa ISO string na may `Z` (`toIso8601String()`)
// sa provider at ni-parse ulit ng `parseManila` sa screen, +8h ulit:
//   2026-09-16 21:06 (Manila)  →  2026-09-17 05:06 AM  ❌
//
// Ang lunas: ipasa ang DateTime mismo mula provider, at `parseManilaValue()`
// ang gamitin sa screen (hindi na nagsi-shift ng DateTime).

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:jireta_loans/core/utils/timezone.dart';
import 'package:jireta_loans/data/models/payment_model.dart';

void main() {
  // 2026-09-16 21:06 Manila = 2026-09-16 13:06 UTC
  const backendUtc = '2026-09-16T13:06:00.000+00:00';

  group('Payment details date — hindi na dinedoble ang +8h', () {
    test('PaymentModel.createdAt ay Manila wall time mula sa true UTC', () {
      final p = PaymentModel.fromJson({
        'id': 'ebae7348-61d7-41f4-b7aa-be1f1e9cb7f',
        'loan_id': 'loan-1',
        'amount': 600,
        'method': 'office_cash',
        'status': 'reversed',
        'created_at': backendUtc,
      });
      expect(p.createdAt.year, 2026);
      expect(p.createdAt.month, 9);
      expect(p.createdAt.day, 16);
      expect(p.createdAt.hour, 21);
      expect(p.createdAt.minute, 6);
    });

    test('parseManilaValue(DateTime mula model) ay hindi na nagdadagdag ng 8h',
        () {
      final manila = parseManila(backendUtc)!;
      final shown = DateFormat('MMM dd, yyyy h:mm a')
          .format(parseManilaValue(manila)!);
      expect(shown, 'Sep 16, 2026 9:06 PM');
    });

    test('parseManilaValue(raw backend string) ay dumaraan pa rin sa +8h shift',
        () {
      final parsed = parseManilaValue(backendUtc)!;
      expect(parsed.day, 16);
      expect(parsed.hour, 21);
    });

    test('ang dating double-parse ay naglalabas ng Sep 17 05:06 AM (regression)',
        () {
      final doubleShifted = parseManila(
          parseManila(backendUtc)!.toIso8601String())!;
      expect(DateFormat('MMM dd, yyyy h:mm a').format(doubleShifted),
          'Sep 17, 2026 5:06 AM');
    });
  });
}
