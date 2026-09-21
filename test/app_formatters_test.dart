// test/app_formatters_test.dart
// Ang `AppFormatters.dateTimeOr` ay ginagamit sa "Submitted: …" (Lender Account
// Upgrade Details). Dati kasing hilaw na ISO slice (`substring(0, 19)`) ang
// ipinapakita — 8 oras mali dahil UTC ito at hindi mabasa ng staff.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:jireta_loans/core/utils/formatters.dart';

void main() {
  // `AppFormatters` ay gumagamit ng `DateFormat(..., 'en_PH')` — kailangan ang
  // locale data bago ito magamit sa test (sa app, sa main() ito ini-initialize).
  setUpAll(() => initializeDateFormatting('en_PH'));

  group('AppFormatters.dateTimeOr', () {
    test('UTC timestamp ay nako-convert sa Manila (+8)', () {
      // 09:29 UTC → 5:29 PM Manila, parehong araw.
      final expected = AppFormatters.dateTime(DateTime(2026, 9, 20, 17, 29));
      expect(
        AppFormatters.dateTimeOr('2026-09-20T09:29:10.000Z'),
        expected,
      );
    });

    test('lumalampas sa susunod na araw kapag 16:00 UTC pataas', () {
      final expected = AppFormatters.dateTime(DateTime(2026, 9, 21, 0, 29));
      expect(
        AppFormatters.dateTimeOr('2026-09-20T16:29:51.064065+00:00'),
        expected,
      );
    });

    test('DateTime na dumaan na sa parseManila ay hindi dinodoble ang +8', () {
      final already = DateTime(2026, 9, 20, 17, 29);
      expect(
        AppFormatters.dateTimeOr(already),
        AppFormatters.dateTime(already),
      );
    });

    test('fallback kapag wala o di-mabasa', () {
      expect(AppFormatters.dateTimeOr(null), '—');
      expect(AppFormatters.dateTimeOr(''), '—');
      expect(AppFormatters.dateTimeOr('hindi petsa'), '—');
      expect(
        AppFormatters.dateTimeOr(null, fallback: 'N/A'),
        'N/A',
      );
    });
  });
}
