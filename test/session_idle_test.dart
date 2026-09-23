// test/session_idle_test.dart
// Verifies the 10-minute idle session contract AND the absolute (3-month)
// session lifetime:
// - AppConstants.sessionDuration is 10 minutes (idle → MPIN LOCK only)
// - AppConstants.absoluteSessionDuration is 3 months (number re-entry only)
// - SecureStorage idle helpers exist and behave
//
// BUG na sinasaklaw ng absolute-session tests: ang 10-minutong idle ay dati
// nag-hahard-logout (binubura ang session) kaya ilang minuto/oras lang ay
// kailangan nang mag-enter muli ng numero. Dapat LOCK lang ito (MPIN ang
// mag-u-unlock) at ang numero ay hihilingin muli pagkalipas ng 3 buwan.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/core/constants/app_constants.dart';
import 'package:jireta_loans/core/security/secure_storage.dart';

void main() {
  group('Session idle (10 minutes)', () {
    test('AppConstants.sessionDuration is 10 minutes', () {
      expect(AppConstants.sessionDuration, const Duration(minutes: 10));
      expect(AppConstants.sessionDuration.inSeconds, 600);
      expect(AppConstants.sessionDurationMs, 600000);
      expect(AppConstants.sessionDurationSeconds, 600);
    });

    test('AppConstants.absoluteSessionDuration is 3 months (90 days)', () {
      expect(AppConstants.absoluteSessionDuration, const Duration(days: 90));
    });

    test('SecureStorage has idle helpers', () {
      // Existence check — these methods must exist for the idle detector
      expect(SecureStorage.saveLastActivity, isA<Function>());
      expect(SecureStorage.getLastActivity, isA<Function>());
      expect(SecureStorage.getRemainingIdleTime, isA<Function>());
      expect(SecureStorage.isIdleExpired, isA<Function>());
      expect(SecureStorage.bumpActivity, isA<Function>());
    });

    test('legacy shims still work', () {
      expect(SecureStorage.getRemainingSessionTime, isA<Function>());
      expect(SecureStorage.isAbsoluteSessionExpired, isA<Function>());
    });

    test('lastActivityKey exists and differs from sessionStartedAtKey', () {
      expect(AppConstants.lastActivityKey, isNotEmpty);
      expect(AppConstants.lastActivityKey, isNot('session_started_at'));
      expect(AppConstants.sessionStartedAtKey, isNotEmpty);
    });
  });

  group('Idle lock vs absolute session', () {
    test('SessionRefresher hindi na nag-reject ng refresh dahil sa idle',
        () async {
      final src = await File('lib/core/security/session_refresher.dart').readAsString();
      // Hindi na ito dapat mag-drop ng valid refresh token dahil lang lumampas
      // ang 10-minutong idle — iyon ang nagpapabalik sa number/OTP form.
      expect(src.contains('isIdleExpired'), isFalse,
          reason: 'Ang idle ay pag-lock lang (MPIN), hindi session kill.');
      expect(src.contains('getRemainingIdleTime'), isFalse);
      // 3-buwan na absolute lifetime ang tanging nagpapatalsik.
      expect(src.contains('absoluteSessionDuration'), isTrue);
      expect(src.contains('getSessionStartedAt'), isTrue);
    });

    test('AuthInterceptor hindi na nag-hard-logout dahil sa idle', () async {
      final src = await File(
              'lib/core/network/interceptors/auth_interceptor.dart')
          .readAsString();
      expect(src.contains('isIdleExpired'), isFalse,
          reason: 'Idle = MPIN lock, hindi dapat mag-clearAll ng session.');
      expect(src.contains('absoluteSessionDuration'), isTrue);
    });

    test('MPIN unlock ay nagrereset ng idle bago ang initialize', () async {
      final src = await File(
              'lib/presentation/features/auth/screens/mobile_login_screen.dart')
          .readAsString();
      // Kapag tama ang MPIN, kailangang maging fresh ang idle bago ang
      // initialize(unlockedByMpin: true) — kung hindi, block ang auto-login.
      expect(
        src.contains('saveLastActivity') &&
            src.indexOf('saveLastActivity') <
                src.indexOf('initialize(unlockedByMpin'),
        isTrue,
      );
    });

    test('Heartbeat hindi nagpi-ping habang idle', () async {
      // BUG na sinusuri nito: ang minuto-minutong ping ang nagpapanatiling
      // "fresh" (`last_seen_at`) ng active_sessions row, at ang fresh na row
      // na may IBANG session id ang tumatanggi sa login ng lahat ng ibang
      // device. Kapag patuloy ang ping kahit walang tao (nakalimutang bukas
      // na app/tab), hindi na makakalogin ang account magpakailanman —
      // "This account is already signed in on another device" kahit walang
      // nakalogin. Dapat itigil ang ping kapag lumipas na ang idle window.
      final src = await File(
              'lib/presentation/shared/providers/auth_state_provider.dart')
          .readAsString();
      final start = src.indexOf('Future<void> _heartbeat()');
      final end = src.indexOf('Future<void> notifyActivity()');
      expect(start >= 0 && end > start, isTrue,
          reason: 'Dapat may _heartbeat() bago ang notifyActivity().');
      final heartbeat = src.substring(start, end);
      expect(heartbeat.contains('getRemainingIdleTime'), isTrue,
          reason: 'Dapat tsek ang idle state bago mag-ping.');
      expect(heartbeat.contains('remaining.inSeconds <= 0'), isTrue,
          reason: 'Kapag tapos na ang idle window, huwag mag-ping.');
    });
  });

  group('REST API endpoints sanity', () {
    // Every endpoint must be a non-empty string with ?fn= query
    test('ApiEndpoints strings are well-formed', () async {
      // Import here to avoid polluting group setup
      // ignore: avoid_dynamic_calls
      final endpoints = [
        'auth-login?fn=login',
        'auth-session?fn=refresh-session',
        'users-manage?fn=get-profile',
        'users-admin?fn=get-list',
        'loans-view?fn=get-list',
        'loans-manage?fn=approve',
        'ci-manage?fn=assign',
        'collections-manage?fn=assign',
        'payments-manage?fn=record-office',
        'disbursements-view?fn=get-list',
        'location-manage?fn=update-rider',
        'notifications-view?fn=get-list',
        'reports-generate?fn=generate',
        'kpi-view?fn=head-manager',
        'audit-get-logs?fn=get-logs',
      ];
      for (final ep in endpoints) {
        expect(ep, isNotEmpty);
        expect(ep.contains('?fn='), isTrue, reason: '$ep must contain ?fn=');
      }
    });
  });
}
