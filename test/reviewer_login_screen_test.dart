// test/reviewer_login_screen_test.dart
//
// Security checks para sa Google Play reviewer sign-in:
//   * Ang screen ay may phone + password fields at nagva-validate bago
//     magpadala ng anumang request (walang OTP field, walang bypass button).
//   * WALANG reviewer phone, password, o secret name na naka-embed sa Flutter
//     sources — ang configuration ay nasa Supabase Edge Function secrets.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/features/auth/screens/reviewer_login_screen.dart';

void main() {
  testWidgets('reviewer form validates before sending any request',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ReviewerLoginScreen()),
      ),
    );

    expect(find.text('Reviewer Sign-In'), findsOneWidget);
    expect(find.text('Sign in as reviewer'), findsOneWidget);
    // Walang OTP field sa reviewer flow.
    expect(find.textContaining('OTP'), findsNothing);

    await tester.tap(find.text('Sign in as reviewer'));
    await tester.pump();

    expect(find.text('Phone number is required'), findsOneWidget);
    expect(find.text('Reviewer password is required'), findsOneWidget);
  });

  test('Flutter sources never embed reviewer credentials or secret names', () {
    final files = [
      'lib/presentation/features/auth/screens/reviewer_login_screen.dart',
      'lib/presentation/features/auth/providers/auth_provider.dart',
      'lib/data/datasources/remote/auth_remote_datasource.dart',
      'lib/core/network/api_endpoints.dart',
    ];
    const forbidden = [
      'REVIEWER_LOGIN_ENABLED',
      'REVIEWER_LENDER_PASSWORD',
      'REVIEWER_RIDER_PASSWORD',
      'REVIEWER_LENDER_PHONE',
      'REVIEWER_RIDER_PHONE',
      '09000000101',
      '09000000102',
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      for (final value in forbidden) {
        expect(
          source.contains(value),
          isFalse,
          reason: '$path must not contain $value',
        );
      }
    }
  });
}
