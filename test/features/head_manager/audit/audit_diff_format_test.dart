// test/features/head_manager/audit/audit_diff_format_test.dart
//
// BEFORE / AFTER ng Audit Logs: dapat madaling basahin ang labels at values
// (hindi `Account Status Id`, hindi raw ISO timestamp), at HINDI tinatanggal
// ang mga field na nasa BEFORE lang.
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:jireta_loans/presentation/features/head_manager/audit/audit_diff_format.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_PH');
  });

  group('humanizeAuditKey', () {
    test('acronym at brand tokens ay tama', () {
      expect(humanizeAuditKey('account_status_id'), 'Account Status ID');
      expect(humanizeAuditKey('profile_photo_url'), 'Profile Photo URL');
      expect(humanizeAuditKey('force_password_change'), 'Force Password Change');
      expect(humanizeAuditKey('email_verified_at'), 'Email Verified At');
      expect(humanizeAuditKey('fcm_token'), 'FCM Token');
      expect(humanizeAuditKey('gcash_reference'), 'GCash Reference');
      expect(humanizeAuditKey('id'), 'ID');
    });
  });

  group('formatAuditValue', () {
    test('null at empty ay em dash', () {
      expect(formatAuditValue(null), '—');
      expect(formatAuditValue('   '), '—');
      expect(formatAuditValue(<dynamic>[]), '—');
    });

    test('boolean ay Yes/No', () {
      expect(formatAuditValue(false), 'No');
      expect(formatAuditValue(true), 'Yes');
    });

    test('raw ISO timestamp → Manila date/time, hindi machine string', () {
      final out = formatAuditValue('2026-09-30T03:44:10.844+00:00');
      expect(out, isNot(contains('T03:44')));
      expect(out, contains('Sep 30, 2026'));
      expect(out, contains('AM'));
    });

    test('nested map ay may humanized keys', () {
      expect(
        formatAuditValue({'profile_photo_url': null, 'amount': 200}),
        'Profile Photo URL: —, Amount: 200',
      );
    });
  });

  group('changedAuditKeys', () {
    test('nagbago lang ang isinasama, pero hindi tinatanggal ang BEFORE-only', () {
      final keys = changedAuditKeys(
        {
          'role': null,
          'account_status_id': '77a9144b',
          'email_verified_at': '2026-09-30T03:44:10.844+00:00',
          'force_password_change': false,
        },
        {'role': 'lender'},
      );

      // Ang talagang nabago ay nasa unahan...
      expect(keys.first, 'role');
      // ...at nananatili pa rin ang mga field ng dating row sa BEFORE.
      expect(keys, contains('account_status_id'));
      expect(keys, contains('email_verified_at'));
      expect(keys, contains('force_password_change'));
    });

    test('walang laman kapag kulang ang isang panig', () {
      expect(changedAuditKeys(null, {'role': 'lender'}), isEmpty);
      expect(changedAuditKeys({'role': 'lender'}, null), isEmpty);
    });
  });
}
