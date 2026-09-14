// Regression test para sa [mobileBottomNavInset]/[mobileBottomNavHeight] at sa
// taas ng floating bottom nav. Sinisiguro nito na:
//
//  1. ang nav ay hindi umaabot sa buong taas ng screen (kung hindi, buong screen
//     ang `bottomWidgetsHeight` nito at ang `MediaQuery.padding.bottom` ng body
//     — dahil `extendBody: true` — ay magiging buong screen din, na
//     nagpapahaba nang sobra sa scroll ng mga screen);
//  2. eksakto ang [mobileBottomNavInset] sa aktwal na taas ng nav — walang
//     kulang (overlap) at walang doble (blangkong espasyo).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
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

  Future<
      ({
        double helper,
        double outsideHelper,
        double bodyPaddingBottom,
        double navHeight,
        double screenHeight,
      })> measure(WidgetTester tester) async {
    double? helper;
    double? outsideHelper;
    double? bodyPaddingBottom;

    final router = GoRouter(
      initialLocation: '/lender/dashboard',
      routes: [
        GoRoute(
          path: '/lender/dashboard',
          builder: (routeCtx, s) {
            // Tulad ng build() ng screen: ang context ay nasa LABAS ng body.
            outsideHelper = mobileBottomNavHeight(routeCtx);
            return MobileScaffold(
              title: 'Account',
              navItems: _navItems,
              body: Builder(
                builder: (ctx) {
                  // Tulad ng widget na ipinasa bilang body — SA LOOB ng body.
                  helper = mobileBottomNavInset(ctx);
                  bodyPaddingBottom = MediaQuery.of(ctx).padding.bottom;
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final pill = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).borderRadius ==
              BorderRadius.circular(32),
    );
    expect(pill, findsOneWidget);

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final navHeight = screenHeight - tester.getRect(pill).top;
    expect(helper, isNotNull);
    expect(outsideHelper, isNotNull);
    expect(bodyPaddingBottom, isNotNull);
    return (
      helper: helper!,
      outsideHelper: outsideHelper!,
      bodyPaddingBottom: bodyPaddingBottom!,
      navHeight: navHeight,
      screenHeight: screenHeight,
    );
  }

  testWidgets('walang safe area (web / desktop)', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    addTearDown(tester.view.reset);

    final r = await measure(tester);
    expect(r.navHeight,
        closeTo(kFloatingNavFloatGap + kFloatingNavPillHeight, 0.01));
    // Hindi dapat buong screen ang nav/body padding.
    expect(r.bodyPaddingBottom, lessThan(r.screenHeight / 2));
    expect(r.bodyPaddingBottom, closeTo(r.navHeight, 0.01));
    expect(r.helper, closeTo(r.navHeight, 0.01));
    expect(r.outsideHelper, closeTo(r.navHeight, 0.01));
  });

  testWidgets('may home indicator (iPhone-like)', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(bottom: 34 * 3);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34 * 3);
    addTearDown(tester.view.reset);

    final r = await measure(tester);
    expect(
      r.navHeight,
      closeTo(34 + kFloatingNavFloatGap + kFloatingNavPillHeight, 0.01),
    );
    expect(r.bodyPaddingBottom, lessThan(r.screenHeight / 2));
    expect(r.bodyPaddingBottom, closeTo(r.navHeight, 0.01));
    expect(r.helper, closeTo(r.navHeight, 0.01));
    expect(r.outsideHelper, closeTo(r.navHeight, 0.01));
  });
}
