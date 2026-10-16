// test/lender_profile_desktop_test.dart
//
// DESKTOP LAYOUT NG LENDER PROFILE (/lender/profile)
//
// Dati, isang column lang ang profile kahit sa desktop — kaya nakaunat ang
// mobile na ayos sa buong browser. Mula sa [kDesktopBreakpoint] pataas:
//
//   * kaliwang rail (360px): identity (avatar / pangalan / status) + bersyon +
//     Log out;
//   * kanang column: ang mga section (Personal, Notifications, Security,
//     General).
//
// Sa ilalim ng breakpoint, isang column pa rin — walang binago sa phone.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/lender/profile/screens/lender_profile_screen.dart';
import 'package:jireta_loans/presentation/shared/widgets/profile/modern_profile_widgets.dart';

import 'helpers/audit_test_helpers.dart';

/// `users-manage?fn=get-profile` na tugon para sa isang VERIFIED na lender —
/// kaya lumalabas ang Personal / Email / Residence Address sections.
Map<String, dynamic> _profileResponse() => {
      'user': {
        'id': '11111111-1111-1111-1111-111111111111',
        'role': 'lender',
        'first_name': 'Blake',
        'middle_name': null,
        'last_name': 'Cruz',
        'suffix': null,
        'email': 'blake@example.com',
        'phone_number': '09441448529',
        'account_status': 'active',
        'force_password_change': false,
        'profile_photo_url': null,
        'created_at': '2026-08-01T10:00:00.000Z',
        'last_login_at': '2026-09-27T10:00:00.000Z',
        'gender': 'male',
        'civil_status': 'single',
        'date_of_birth': '1998-04-12T00:00:00.000Z',
        'street_address': '12 Mabini St',
        'barangay': 'Poblacion',
        'city': 'Makati',
        'province': 'Metro Manila',
        'zip_code': '1210',
        'account_upgrade_status': 'verified',
      },
    };

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
    GetIt.instance.registerLazySingleton<UserRemoteDataSource>(
      () => UserRemoteDataSource(
        FakeDioClient((o) async => Response<dynamic>(
              requestOptions: o,
              data: _profileResponse(),
            )),
      ),
    );
  });

  tearDownAll(() => GetIt.instance.reset());

  Future<void> pumpProfile(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/lender/profile',
      routes: [
        GoRoute(
          path: '/lender/profile',
          builder: (_, __) => const LenderProfileScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    // Kailangan ng ilang frame para sa async na loadProfile + ang
    // collapse/expand at avatar-load na animations.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('Lender profile desktop layout', () {
    testWidgets('1280px: dalawang column — kaliwang rail + mga section',
        (tester) async {
      await pumpProfile(tester, 1280);

      expect(find.byType(ModernProfileHeader), findsOneWidget);
      // Ang pangalan ay nasa header AT sa "Full name" row ng Personal Details.
      expect(find.text('Blake Cruz'), findsWidgets);

      final header = tester.getTopLeft(find.byType(ModernProfileHeader));
      // `ModernSectionLabel` ay nag-uuppercase — "PERSONAL".
      final sections = tester.getTopLeft(find.text('PERSONAL'));

      // Magkatabi: nasa KANAN ng header ang mga section (hindi sa ilalim).
      expect(sections.dx, greaterThan(header.dx + 300),
          reason: 'Hindi magkatabi ang identity rail at ang mga section');
      expect((sections.dy - header.dy).abs(), lessThan(80),
          reason: 'Nasa ibaba (hindi katabi) ang mga section');

      // Nasa kaliwang rail din ang account actions (bersyon + Log out) — nasa
      // KALIWA ito ng mga section, hindi sa kanang column.
      final logout = tester.getTopLeft(find.text('Log out'));
      expect(logout.dx, lessThan(sections.dx));
      expect(tester.takeException(), isNull);
    });

    testWidgets('950px (katabi ng breakpoint): walang overflow',
        (tester) async {
      await pumpProfile(tester, 950);

      expect(find.byType(ModernProfileHeader), findsOneWidget);
      expect(find.text('PERSONAL'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Makitid na desktop: dapat katabi pa rin (hindi na-stack) ang rail.
      final header = tester.getTopLeft(find.byType(ModernProfileHeader));
      final sections = tester.getTopLeft(find.text('PERSONAL'));
      expect(sections.dx, greaterThan(header.dx + 300));
    });

    testWidgets('390px: isang column pa rin (walang binago sa phone)',
        (tester) async {
      await pumpProfile(tester, 390);

      expect(find.byType(ModernProfileHeader), findsOneWidget);

      final header = tester.getTopLeft(find.byType(ModernProfileHeader));
      final sections = tester.getTopLeft(find.text('PERSONAL'));

      // Nasa IBABA ng header ang mga section — pareho ang kaliwang gilid.
      expect(sections.dy, greaterThan(header.dy),
          reason: 'Hindi na-stack ang mga section sa ilalim ng header');
      expect((sections.dx - header.dx).abs(), lessThan(24));
    });
  });
}
