// test/rider_desktop_layout_test.dart
//
// Desktop layout ng RIDER role.
//
// Dati, ang mga rider screen ay laging mobile chrome (navy app bar + floating
// bottom nav) — kahit sa desktop, kaya nakaunat ang mobile UI sa buong
// browser. Mula sa [kDesktopBreakpoint] pataas, ang rider ay gumagamit na ng
// KAPAREHONG desktop shell ng head manager / employee / lender (sidebar + top
// bar), at wala nang floating bottom nav. Sa ilalim ng breakpoint, hindi
// nagbabago ang mobile UI — kaya hindi ito umaapekto sa phone.
//
// Apat lang ang navigation item ng rider sidebar: Home, Collections, CI Tasks,
// History. Ang Profile at Log Out ay nasa account section sa ibaba.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/core/constants/route_constants.dart';
import 'package:jireta_loans/core/theme/app_colors.dart';
import 'package:jireta_loans/core/theme/app_theme.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/presentation/shared/widgets/layout/mobile_scaffold.dart';
import 'package:jireta_loans/presentation/shared/widgets/profile_avatar.dart';

import 'helpers/audit_test_helpers.dart';

const _riderNavItems = [
  MobileNavItem(
    icon: Icons.home_outlined,
    activeIcon: Icons.home,
    label: 'Home',
    route: RouteConstants.riderDashboard,
  ),
  MobileNavItem(
    icon: Icons.delivery_dining_outlined,
    activeIcon: Icons.delivery_dining,
    label: 'Collections',
    route: RouteConstants.riderCollections,
  ),
  MobileNavItem(
    icon: Icons.search_outlined,
    activeIcon: Icons.search,
    label: 'CI Tasks',
    route: RouteConstants.riderCi,
  ),
  MobileNavItem(
    icon: Icons.history_outlined,
    activeIcon: Icons.history_rounded,
    label: 'History',
    route: RouteConstants.riderHistory,
  ),
  MobileNavItem(
    icon: Icons.person_outline,
    activeIcon: Icons.person,
    label: 'Profile',
    route: RouteConstants.riderProfile,
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

  Future<void> pumpRider(
    WidgetTester tester,
    double width, {
    String location = '/rider/dashboard',
    bool showBackButton = false,
    ThemeMode themeMode = ThemeMode.light,
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
            // Kapareho ng totoong rider dashboard screen.
            title: 'Rider Home',
            navItems: _riderNavItems,
            accentColor: AppColors.riderGreen,
            showBackButton: showBackButton,
            appBarActions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                tooltip: 'Refresh',
                onPressed: () {},
              ),
            ],
            body: const Center(child: Text('rider content')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Ang sidebar ng rider ay BERDE (role color) — gradient na may
  /// [AppColors.riderGreen] — hindi navy.
  Finder greenSidebar() => find.byWidgetPredicate((w) {
        if (w is! AnimatedContainer) return false;
        final d = w.decoration;
        if (d is! BoxDecoration || d.gradient is! LinearGradient) return false;
        return (d.gradient as LinearGradient)
            .colors
            .contains(AppColors.riderGreen);
      });

  /// Ang floating bottom nav pill ay may makapal na rounded border (radius 32).
  Finder floatingNavPill() => find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).borderRadius ==
                BorderRadius.circular(32),
      );

  group('Rider desktop layout', () {
    testWidgets('1280px: sidebar ang navigation, walang floating bottom nav',
        (tester) async {
      await pumpRider(tester, 1280);

      expect(tester.takeException(), isNull);
      // Desktop chrome: sidebar (may toggle sa top bar, may JIRETA header).
      expect(find.byTooltip('Toggle Sidebar'), findsOneWidget);
      expect(find.text('JIRETA'), findsOneWidget);
      // Limang navigation item ang laman ng rider sidebar — kasama na ang
      // Cash Deliveries.
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Collections'), findsOneWidget);
      expect(find.text('Deliveries'), findsOneWidget);
      expect(find.text('CI Tasks'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      // Profile at Log Out ay nasa account section sa ibaba ng sidebar.
      expect(find.text('My Profile'), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);
      // Wala nang avatar/identity (+ dropdown) sa top bar — nasa sidebar na.
      expect(find.byType(ProfileAvatar), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
      // Wala nang floating bottom nav pill sa desktop.
      expect(floatingNavPill(), findsNothing);
      // Isang beses lang ang body, at may screen title sa top bar.
      expect(find.text('Rider Home'), findsOneWidget);
      expect(find.text('rider content'), findsOneWidget);
      // Nananatili ang app bar actions (navy pill — puting icon sa puting bar).
      expect(find.byTooltip('Refresh'), findsOneWidget);
    });

    testWidgets('390px: hindi nagbabago — mobile chrome pa rin',
        (tester) async {
      await pumpRider(tester, 390);

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Toggle Sidebar'), findsNothing);
      expect(floatingNavPill(), findsOneWidget);
      // Bottom nav pa rin ang navigation — walang sidebar labels.
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('CI Tasks'), findsOneWidget);
      expect(find.text('My Profile'), findsNothing);
      expect(find.text('Log Out'), findsNothing);
      // Sidebar-only ang Deliveries — wala sa mobile bottom nav ng dashboard.
      expect(find.text('Deliveries'), findsNothing);
      expect(find.text('rider content'), findsOneWidget);
    });

    testWidgets('desktop detail screen: may back button sa top bar',
        (tester) async {
      await pumpRider(tester, 1280, showBackButton: true);

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Back'), findsOneWidget);
    });

    testWidgets('desktop: BERDE ang sidebar ng rider (role color)',
        (tester) async {
      await pumpRider(tester, 1280);

      expect(tester.takeException(), isNull);
      expect(greenSidebar(), findsOneWidget);
    });

    testWidgets('desktop dark mode: madilim ang page, hindi puting-puti',
        (tester) async {
      await pumpRider(tester, 1280, themeMode: ThemeMode.dark);

      expect(tester.takeException(), isNull);
      // Dati, laging #F0F2F5 ang desktop page — kaya puti ang background habang
      // puti rin ang text ng mga theme-aware na widget: "invisible" ang
      // greeting, pangalan, at section labels. Ngayon, dark page na ito.
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, AppColors.darkPageBg);
      // Nananatiling berde ang sidebar sa dark mode.
      expect(greenSidebar(), findsOneWidget);
    });

    testWidgets('desktop: naka-highlight ang section ng kasalukuyang path',
        (tester) async {
      // Ang collection details ay nasa ilalim ng "Collections" section.
      await pumpRider(tester, 1280, location: '/rider/collections/abc');

      bool isHighlighted(String label) => tester
          .widgetList<AnimatedContainer>(find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          ))
          .any((c) =>
              (c.decoration as BoxDecoration?)?.color ==
              AppColors.gold.withValues(alpha: 0.15));

      expect(isHighlighted('Collections'), isTrue,
          reason: 'Hindi naka-highlight ang Collections sa details screen');
      expect(isHighlighted('History'), isFalse);
    });
  });
}
