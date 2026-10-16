// test/lender_desktop_layout_test.dart
//
// Desktop layout ng LENDER role.
//
// Dati, ang mga lender screen ay laging mobile chrome (navy app bar + floating
// bottom nav) — kahit sa desktop, kaya nakaunat ang mobile UI sa buong browser.
// Mula sa [kDesktopBreakpoint] pataas, ang lender role ay gumagamit na ng
// KAPAREHONG desktop shell ng head manager / employee (sidebar + top bar), at
// wala nang floating bottom nav. Sa ilalim ng breakpoint, hindi nagbabago ang
// mobile UI — kaya hindi ito umaapekto sa phone.
//
// Ang lender sidebar ay TATLONG items lang: Dashboard, Payments, Transactions.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/core/theme/app_colors.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/presentation/shared/widgets/layout/mobile_scaffold.dart';

import 'helpers/audit_test_helpers.dart';

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

  Future<void> pumpLender(
    WidgetTester tester,
    double width, {
    String location = '/lender/dashboard',
    bool showBackButton = false,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: location,
          builder: (_, __) => MobileScaffold(
            // Kapareho ng totoong lender dashboard screen.
            title: 'Account',
            navItems: lenderNavItems(),
            showBackButton: showBackButton,
            appBarActions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                tooltip: 'Refresh',
                onPressed: () {},
              ),
            ],
            body: const Center(child: Text('lender content')),
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

  /// Ang floating bottom nav pill ay may makapal na rounded border (radius 32).
  Finder floatingNavPill() => find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).borderRadius ==
                BorderRadius.circular(32),
      );

  group('Lender desktop layout', () {
    testWidgets('1280px: sidebar ang navigation, walang floating bottom nav',
        (tester) async {
      await pumpLender(tester, 1280);

      expect(tester.takeException(), isNull);
      // Desktop chrome: sidebar (may toggle sa top bar, may JIRETA header).
      expect(find.byTooltip('Toggle Sidebar'), findsOneWidget);
      expect(find.text('JIRETA'), findsOneWidget);
      // TATLONG item lang ang laman ng lender sidebar.
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Payments'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
      // Nakatago ang ibang lender sections sa side nav.
      expect(find.text('Loans'), findsNothing);
      expect(find.text('Collections'), findsNothing);
      expect(find.text('Documents'), findsNothing);
      expect(find.text('Account Upgrade'), findsNothing);
      expect(find.text('Profile'), findsNothing);
      // Wala nang floating bottom nav pill sa desktop.
      expect(floatingNavPill(), findsNothing);
      expect(find.text('Home'), findsNothing);
      // Isang beses lang ang body, at may screen title sa top bar.
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('lender content'), findsOneWidget);
      // Nananatili ang app bar actions (navy pill — puting icon sa puting bar).
      expect(find.byTooltip('Refresh'), findsOneWidget);
    });

    testWidgets('390px: hindi nagbabago — mobile chrome pa rin',
        (tester) async {
      await pumpLender(tester, 390);

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Toggle Sidebar'), findsNothing);
      expect(floatingNavPill(), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      // Sidebar-only na mga label — wala sa mobile bottom nav.
      expect(find.text('Transactions'), findsNothing);
      expect(find.text('Dashboard'), findsNothing);
      expect(find.text('lender content'), findsOneWidget);
    });

    testWidgets('desktop detail screen: may back button sa top bar',
        (tester) async {
      await pumpLender(tester, 1280, showBackButton: true);

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Back'), findsOneWidget);
    });

    testWidgets('desktop: naka-highlight ang section ng kasalukuyang path',
        (tester) async {
      // Ang GCash payment screen ay nasa ilalim ng "Payments" section.
      await pumpLender(tester, 1280, location: '/lender/pay-gcash');

      bool isHighlighted(String label) => tester
          .widgetList<AnimatedContainer>(find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          ))
          .any((c) =>
              (c.decoration as BoxDecoration?)?.color ==
              AppColors.gold.withValues(alpha: 0.15));

      expect(isHighlighted('Payments'), isTrue,
          reason: 'Hindi naka-highlight ang Payments sa pay-gcash screen');
      expect(isHighlighted('Transactions'), isFalse);
    });
  });
}
