// test/lender_sidebar_account_test.dart
//
// MY PROFILE + LOG OUT SA SIDEBAR NG LENDER
//
// Ang lender ay dating may avatar dropdown sa top bar na may "My Profile" at
// "Log Out". Ngayon, nakapin na ang dalawang iyon sa ibaba ng SIDEBAR (account
// section) at HINDI na ipinapakita ang avatar/identity sa top bar — walang
// doble at walang dead na dropdown. Nananatili ang puting hitsura ng Log Out
// (ordinaryong nav item, hindi babala).
//
// Ang HM / employee ay hindi apektado: dropdown pa rin nila ang avatar.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/core/theme/app_colors.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/presentation/shared/widgets/layout/mobile_scaffold.dart';

import 'helpers/audit_test_helpers.dart';

const _navItems = [
  MobileNavItem(
    icon: Icons.home_outlined,
    activeIcon: Icons.home,
    label: 'Home',
    route: '/lender/dashboard',
  ),
  MobileNavItem(
    icon: Icons.payments_outlined,
    activeIcon: Icons.payments,
    label: 'Payments',
    route: '/lender/payments',
  ),
  MobileNavItem(
    icon: Icons.receipt_long_outlined,
    activeIcon: Icons.receipt_long,
    label: 'Transaction',
    route: '/lender/transactions',
  ),
  MobileNavItem(
    icon: Icons.person_outlined,
    activeIcon: Icons.person,
    label: 'Profile',
    route: '/lender/profile',
  ),
];

void main() {
  setUpAll(() async {
    await loadTestEnv();
    GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
      () => NotificationRemoteDataSource(
        FakeDioClient((o) async => Response<dynamic>(
              requestOptions: o,
              data: {
                'data': <dynamic>[],
                'meta': {'unread_count': 0},
              },
            )),
      ),
    );
  });

  tearDownAll(() => GetIt.instance.reset());

  /// Isang lender screen (MobileScaffold) na may desktop breakpoint — kapareho
  /// ng totoong lender screens, kaya ang desktop chrome (sidebar + top bar) ang
  /// tumatakbo sa 1280px.
  Future<void> pumpLender(
    WidgetTester tester,
    double width, {
    String location = '/lender/dashboard',
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/lender/dashboard',
          builder: (_, __) => MobileScaffold(
            title: 'Account',
            navItems: _navItems,
            body: const Center(child: Text('lender content')),
          ),
        ),
        GoRoute(
          path: '/lender/profile',
          builder: (_, __) => MobileScaffold(
            title: 'Profile',
            navItems: _navItems,
            body: const Center(child: Text('profile content')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Color? textColor(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style?.color;

  group('Lender sidebar account items', () {
    testWidgets('desktop: My Profile at Log Out nasa sidebar, puti ang logout',
        (tester) async {
      await pumpLender(tester, 1280);
      expect(tester.takeException(), isNull);

      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);

      // Puti (kapareho ng ibang sidebar item) — HINDI pula.
      expect(textColor(tester, 'Log Out'), Colors.white70);
      expect(textColor(tester, 'Log Out'), isNot(AppColors.error));
      final logoutIcon =
          tester.widget<Icon>(find.byIcon(Icons.logout));
      expect(logoutIcon.color, Colors.white54);

      // Nakatago na ang avatar / identity (pangalan + role) sa top bar: nasa
      // sidebar na ang lahat ng laman ng dropdown nito.
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.text('LENDER'), findsNothing);
    });

    testWidgets('desktop: tap Log Out → confirm modal ("Are you sure")',
        (tester) async {
      await pumpLender(tester, 1280);

      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();

      expect(find.text('Are you sure to logout?'), findsOneWidget);

      // "No" → nagsasara lang, hindi nag-logout.
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(find.text('Are you sure to logout?'), findsNothing);
      expect(find.text('lender content'), findsOneWidget);
    });

    testWidgets('desktop: tap My Profile → /lender/profile', (tester) async {
      await pumpLender(tester, 1280);

      await tester.tap(find.text('My Profile'));
      await tester.pumpAndSettle();

      expect(find.text('profile content'), findsOneWidget);
      // Naka-highlight ang My Profile sa sarili nitong screen.
      expect(textColor(tester, 'My Profile'), AppColors.gold);
    });

    testWidgets('mobile (390px): hindi ito dinadagdag sa floating bottom nav',
        (tester) async {
      await pumpLender(tester, 390);
      expect(tester.takeException(), isNull);

      // Desktop sidebar lang ang account section (My Profile / Log Out) — sa
      // phone, hindi ito dinadagdag sa floating bottom nav: sapat na ang
      // "Profile" tab doon.
      expect(find.text('My Profile'), findsNothing);
      expect(find.text('Log Out'), findsNothing);
      expect(find.text('Profile'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
