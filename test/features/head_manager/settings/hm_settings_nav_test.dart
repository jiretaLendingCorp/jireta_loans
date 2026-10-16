// test/features/head_manager/settings/hm_settings_nav_test.dart
//
// Ang "Settings" ng Head Manager ay nasa PROFILE DROPDOWN (itaas-kanan), hindi
// na sa side nav bar.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jireta_loans/core/di/injection.dart';
import 'package:jireta_loans/data/datasources/remote/auth_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/profile/providers/hm_profile_provider.dart';
import 'package:jireta_loans/presentation/shared/providers/auth_state_provider.dart';
import 'package:jireta_loans/presentation/shared/widgets/layout/web_scaffold.dart';

import '../../../helpers/audit_test_helpers.dart';

UserModel _headManager() => UserModel(
      id: 'hm-1',
      role: 'head_manager',
      firstName: 'Mylene',
      lastName: 'Cayabyab',
      accountStatus: 'active',
      forcePasswordChange: false,
      createdAt: DateTime.now(),
    );

class _FakeAuthNotifier extends AuthStateNotifier {
  _FakeAuthNotifier() {
    state = AuthState(isAuthenticated: true, user: _headManager());
  }
}

class _FakeProfileNotifier extends HmProfileNotifier {
  _FakeProfileNotifier(super.userDs, super.authDs);

  @override
  Future<void> loadProfile({bool silent = false}) async {
    state = HmProfileState(user: _headManager());
  }
}

Future<void> pumpScaffold(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/hm/dashboard',
    routes: [
      GoRoute(
        path: '/hm/dashboard',
        builder: (_, __) => const WebScaffold(
          title: 'Dashboard',
          body: Center(child: Text('content')),
        ),
      ),
      // Ang totoong settings route ay HmSettingsScreen; dito sapat na ang
      // marker para mapatunayang na-navigate ito.
      GoRoute(
        path: '/hm/settings',
        builder: (_, __) => const Scaffold(body: Text('settings page')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      authStateProvider.overrideWith((ref) => _FakeAuthNotifier()),
      hmProfileProvider.overrideWith(
        (ref) => _FakeProfileNotifier(
          sl<UserRemoteDataSource>(),
          sl<AuthRemoteDataSource>(),
        ),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadTestEnv);

  setUp(() async {
    sl.allowReassignment = true;
    await setupDependencies();
  });

  tearDown(() => sl.reset());

  testWidgets('wala na ang Settings sa side nav bar', (tester) async {
    await pumpScaffold(tester);

    expect(find.text('Settings'), findsNothing);
    // Katibayan na Head Manager nav items ang naka-render.
    expect(find.text('Audit Logs'), findsOneWidget);
  });

  testWidgets('nasa profile dropdown ang Settings at nagna-navigate ito',
      (tester) async {
    await pumpScaffold(tester);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('settings page'), findsOneWidget);
  });
}
