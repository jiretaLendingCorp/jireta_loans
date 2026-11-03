// test/delete_account_screen_test.dart
//
// Google Play Delete Account page:
//   * PUBLIC ang page — nagre-render kahit walang session at may request form.
//   * Naka-log-in na lender/rider → may agarang deletion card.
//   * Nagva-validate bago magpadala ng request.
//   * Nakatala ang route/endpoint sa source (walang typo na tahimik na 404).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/features/account/screens/delete_account_screen.dart';
import 'package:jireta_loans/presentation/shared/providers/auth_state_provider.dart';

class _FakeAuthNotifier extends AuthStateNotifier {
  _FakeAuthNotifier(AuthState initial) {
    state = initial;
  }
}

UserModel _lender() => UserModel(
      id: 'lender-1',
      role: 'lender',
      firstName: 'Ana',
      lastName: 'Cruz',
      accountStatus: 'active',
      forcePasswordChange: false,
      createdAt: DateTime.now(),
    );

Future<void> _pump(
  WidgetTester tester, {
  bool signedIn = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _FakeAuthNotifier(
            signedIn
                ? AuthState(isAuthenticated: true, user: _lender())
                : const AuthState(),
          ),
        ),
      ],
      child: const MaterialApp(home: DeleteAccountScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('public page: walang login, may deletion request form',
      (tester) async {
    await _pump(tester);

    expect(find.text('Delete Account'), findsOneWidget);
    expect(find.text('Delete your Jireta Loans account'), findsOneWidget);
    expect(find.text('What will be deleted'), findsOneWidget);
    expect(find.text('What we keep'), findsOneWidget);
    expect(find.text('Request deletion without signing in'), findsOneWidget);
    expect(find.text('Submit deletion request'), findsOneWidget);

    // Walang instant-delete card kapag walang session.
    expect(find.text('Delete this account now'), findsNothing);
  });

  testWidgets('public form validates identifier at full name', (tester) async {
    await _pump(tester);

    await tester.ensureVisible(find.text('Submit deletion request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit deletion request'));
    await tester.pump();

    expect(
      find.text('Enter your registered mobile number or email.'),
      findsOneWidget,
    );
    expect(find.text('Enter the full name on the account.'), findsOneWidget);
  });

  testWidgets('signed-in lender: may instant deletion at manual request',
      (tester) async {
    await _pump(tester, signedIn: true);

    expect(find.text('Delete this account now'), findsOneWidget);
    expect(find.text('Type DELETE to confirm'), findsOneWidget);
    expect(find.text('Delete my account'), findsOneWidget);
    expect(
      find.text('Submit a request for manual review instead'),
      findsOneWidget,
    );
    expect(find.text('Request deletion without signing in'), findsNothing);
  });

  test('route, endpoint, at public router registration ay naka-wire', () {
    final route =
        File('lib/core/constants/route_constants.dart').readAsStringSync();
    final router = File('lib/core/router/app_router.dart').readAsStringSync();
    final datasource = File(
      'lib/data/datasources/remote/account_deletion_remote_datasource.dart',
    ).readAsStringSync();
    final endpoints =
        File('lib/core/network/api_endpoints.dart').readAsStringSync();

    expect(route, contains("deleteAccount = '/delete-account'"));
    expect(router, contains('DeleteAccountScreen'));
    expect(router, contains('RouteConstants.deleteAccount'));
    expect(endpoints,
        contains("accountDeleteRequest = 'account-delete?fn=request'"));
    expect(endpoints,
        contains("accountDeleteSelf = 'account-delete?fn=delete-self'"));
    expect(datasource, contains('ApiEndpoints.accountDeleteRequest'));
    expect(datasource, contains('ApiEndpoints.accountDeleteSelf'));

    // Ang public page ay hindi dapat i-bounce sa dashboard ng role.
    expect(
      router.contains('path != RouteConstants.deleteAccount'),
      isTrue,
      reason: 'signed-in users must be able to stay on /delete-account',
    );
  });
}
