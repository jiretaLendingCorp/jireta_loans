// test/employee_mfa_web_login_test.dart
//
// Kapag naka-enroll ang employee sa authenticator (TOTP), hindi siya dapat
// deretsong makapasok sa dashboard pagkatapos ng email/password login. Ang
// web login screen ang nagdadala sa `/mfa-verify`; ang gate mismo ay nasa
// `AuthNotifier.login` (nasusubukan sa `employee_mfa_flow_test.dart`).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jireta_loans/core/constants/route_constants.dart';
import 'package:jireta_loans/core/security/mfa_service.dart';
import 'package:jireta_loans/data/datasources/remote/auth_remote_datasource.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/features/auth/providers/auth_provider.dart';
import 'package:jireta_loans/presentation/features/auth/screens/web_login_screen.dart';
import 'package:jireta_loans/presentation/shared/providers/auth_state_provider.dart';
import 'package:jireta_loans/presentation/shared/providers/connectivity_provider.dart';

class _NoopAuthRemoteDataSource implements AuthRemoteDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Sinesenyas ng fake ang parehong resulta ng totoong `AuthNotifier.login`:
/// authenticated agad, pero may MFA gate kapag naka-enroll.
class _FakeLoginNotifier extends AuthNotifier {
  _FakeLoginNotifier(this.authState, {required this.mfaEnabled})
      : super(_NoopAuthRemoteDataSource(), authState);

  final AuthStateNotifier authState;
  final bool mfaEnabled;

  @override
  LoginMfaInfo get loginMfa => mfaEnabled
      ? const LoginMfaInfo(
          enabled: true,
          factorId: 'factor-1',
          friendlyName: 'Authenticator',
        )
      : const LoginMfaInfo.unknown();

  @override
  Future<bool> login({required String email, required String password}) async {
    authState.setAuthenticated(UserModel(
      id: '11111111-1111-1111-1111-111111111111',
      role: 'employee',
      email: email,
      firstName: 'Em',
      lastName: 'Ployee',
      accountStatus: 'active',
      forcePasswordChange: false,
      createdAt: DateTime.now(),
    ));
    if (mfaEnabled) await authState.requireMfa();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpLogin(WidgetTester tester,
      {required bool mfaEnabled}) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final authState = AuthStateNotifier();
    final notifier = _FakeLoginNotifier(authState, mfaEnabled: mfaEnabled);

    final router = GoRouter(
      initialLocation: RouteConstants.webLogin,
      routes: [
        GoRoute(
          path: RouteConstants.webLogin,
          builder: (_, __) => const WebLoginScreen(),
        ),
        GoRoute(
          path: RouteConstants.mfaVerify,
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('MFA screen'))),
        ),
        GoRoute(
          path: RouteConstants.empDashboard,
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('Employee dashboard'))),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        connectivityProvider.overrideWith((ref) => Stream<bool>.value(true)),
        authStateProvider.overrideWith((ref) => authState),
        authProvider.overrideWith((ref) => notifier),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // Test-font artifact: sumosobra ang "Don't have an account? Register"
    // row kapag parisukat ang glyphs. Hindi ito lumalabas sa totoong font.
    tester.takeException();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(
        find.byType(TextFormField).at(0), 'employee@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('may TOTP → /mfa-verify, hindi dashboard', (tester) async {
    await pumpLogin(tester, mfaEnabled: true);
    await submit(tester);

    expect(find.text('MFA screen'), findsOneWidget);
    expect(find.text('Employee dashboard'), findsNothing);

    // I-dispose ang tree para mawala ang auth heartbeat timer.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('walang TOTP → deretso sa employee dashboard', (tester) async {
    await pumpLogin(tester, mfaEnabled: false);
    await submit(tester);

    expect(find.text('Employee dashboard'), findsOneWidget);
    expect(find.text('MFA screen'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
