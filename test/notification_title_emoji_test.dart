// test/notification_title_emoji_test.dart
//
// BUG: "▌Account Upgrade Submitted" — ang title sa notification list ay may
// naka-prefix na emoji (idinadagdag ng `decorateNotificationTitle` sa
// supabase/functions/_shared/notifications.ts para sa FCM push), pero ang app
// font stack ay `Inter` na WALANG emoji glyph at walang color-emoji fallback
// sa web (CanvasKit) — kaya nagre-render ito bilang `.notdef` ng Inter:
// manipis na vertical bar sa unahan ng title.
//
// FIX: tinatanggal ang emoji prefix sa `NotificationModel` (isa lang ang
// ayos, lahat ng notification screen) — ang per-type na colored icon ang
// kumakatawan sa uri.

import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/data/models/notification_model.dart';

NotificationModel _model(String title) => NotificationModel.fromJson({
      'id': 'n1',
      'user_id': 'u1',
      'title': title,
      'body': 'body',
      'type': 'account_upgrade_submitted',
      'is_read': false,
      'created_at': '2026-09-24T00:00:00Z',
    });

void main() {
  group('stripNotificationEmoji', () {
    test('tinatanggal ang emoji prefix at ang sumusunod na space', () {
      expect(stripNotificationEmoji('⭐ Account Upgrade Submitted'),
          'Account Upgrade Submitted');
      expect(stripNotificationEmoji('💰 Payment Verified'),
          'Payment Verified');
      expect(stripNotificationEmoji('🚚 New Collection Request'),
          'New Collection Request');
      expect(stripNotificationEmoji('📋 CI Report Submitted'),
          'CI Report Submitted');
    });

    test('emoji na may variation selector (⚠️ ↩️)', () {
      expect(stripNotificationEmoji('⚠️ Penalty Applied'), 'Penalty Applied');
      expect(stripNotificationEmoji('↩️ Payment Reversed'),
          'Payment Reversed');
    });

    test('hindi ginagalaw ang title na walang emoji prefix', () {
      expect(stripNotificationEmoji('Account Upgrade Submitted'),
          'Account Upgrade Submitted');
      // Gitnang em dash — hindi ito prefix, kaya dapat manatili.
      expect(stripNotificationEmoji('CI Report Submitted — Awaiting Review'),
          'CI Report Submitted — Awaiting Review');
    });

    test('blangko / walang laman ay hindi sumasabog', () {
      expect(stripNotificationEmoji(''), '');
      expect(stripNotificationEmoji('   '), '');
    });

    test('maramihang emoji prefix', () {
      expect(stripNotificationEmoji('🎉🎉 Loan Approved'), 'Loan Approved');
    });
  });

  group('NotificationModel.fromJson', () {
    test('wala nang emoji sa title ng app', () {
      expect(_model('⭐ Account Upgrade Submitted').title,
          'Account Upgrade Submitted');
    });

    test('plain na title ay hindi binabago', () {
      expect(_model('New Collection Request').title, 'New Collection Request');
    });

    test('nananatili ang type / body / isRead', () {
      final n = _model('⭐ Account Upgrade Submitted');
      expect(n.type, 'account_upgrade_submitted');
      expect(n.body, 'body');
      expect(n.isRead, isFalse);
    });
  });
}
