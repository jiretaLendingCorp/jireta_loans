// test/features/head_manager/dashboard/hm_activity_feed_test.dart
//
// Recent Activity ng Head Manager: ang mga GCash/Xendit action ay dating
// lumalabas na "Generate Gcash Link" / "Xendit Payment Synced" na may subtitle
// na "System • payments" — parang raw log, at mali ang capitalization.
// Sinusuri dito ang friendly na pamagat, tamang "GCash", at ang amount mula sa
// `new_values` kapag may confirmed payment.
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/presentation/features/head_manager/dashboard/widgets/hm_activity_feed.dart';

Map<String, dynamic> auditRow({
  required String action,
  Map<String, dynamic>? newValues,
  Map<String, dynamic>? user,
  String table = 'payments',
}) =>
    {
      'id': '11111111-1111-1111-1111-111111111111',
      'action': action,
      'table_name': table,
      'record_id': '22222222-2222-2222-2222-222222222222',
      'new_values': newValues,
      'created_at': '2026-10-18T10:30:00.000Z',
      'performed_by': user == null ? null : 'user-1',
      'performed_by_user': user,
    };

void main() {
  group('HM Recent Activity — GCash entries', () {
    test('generate_gcash_link: "initiated", hindi "link generated"', () {
      final e = activityEventFromAuditLog(auditRow(
        action: 'generate_gcash_link',
        user: {'first_name': 'PrinCess', 'last_name': 'Armallyn'},
      ));

      expect(e.title, 'GCash payment initiated');
      expect(e.title.toLowerCase(), isNot(contains('link')));
      expect(e.subtitle, 'PrinCess Armallyn');
      expect(e.subtitle.toLowerCase(), isNot(contains('payments')));
    });

    test('xendit_payment_synced: "paid" + amount, hindi "System • payments"', () {
      final e = activityEventFromAuditLog(auditRow(
        action: 'xendit_payment_synced',
        newValues: {'amount': 200, 'xendit_id': 'x-1', 'source': 'sync'},
      ));

      expect(e.title, 'GCash payment paid');
      expect(e.subtitle, 'System • ₱200.00');
      expect(e.title.toLowerCase(), isNot(contains('confirm')));
    });

    test('xendit_payment_verified: bayad na (Paid)', () {
      final e = activityEventFromAuditLog(auditRow(
        action: 'xendit_payment_verified',
        newValues: {'amount': 1250.5, 'source': 'webhook'},
      ));

      expect(e.title, 'GCash payment paid');
      expect(e.subtitle, 'System • ₱1,250.50');
    });

    test('iba pang action: label pa rin ng catalog + table context', () {
      final e = activityEventFromAuditLog(auditRow(
        action: 'collection_approve',
        table: 'collections',
        user: {'first_name': 'Juan', 'last_name': 'Dela Cruz'},
      ));

      expect(e.title, 'Collection Approve');
      expect(e.subtitle, 'Juan Dela Cruz • collections');
    });
  });
}
