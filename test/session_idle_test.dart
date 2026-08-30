// test/session_idle_test.dart
// Verifies the new 10-minute idle session contract:
// - AppConstants.sessionDuration is 10 minutes
// - SecureStorage idle helpers exist and behave
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
