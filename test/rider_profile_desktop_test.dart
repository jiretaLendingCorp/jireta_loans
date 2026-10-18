// test/rider_profile_desktop_test.dart
//
// DESKTOP LAYOUT NG RIDER PROFILE (/rider/profile)
//
// Dati, isang column lang ang profile kahit sa desktop — kaya nakaunat ang
// mobile na ayos sa buong browser. Mula sa [kDesktopBreakpoint] pataas:
//
//   * kaliwang rail (360px): identity (avatar / pangalan / status) + bersyon +
//     Log out;
//   * kanang column: ang mga section (Personal, Appearance & Alerts, Security,
//     General).
//
// Kasama rin sa Security ang Two-Factor Authentication (MFA / TOTP) — kapareho
// ng lender profile. Sa ilalim ng breakpoint, isang column pa rin.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/rider/profile/screens/rider_profile_screen.dart';
import 'package:jireta_loans/presentation/shared/widgets/profile/modern_profile_widgets.dart';
import 'package:jireta_loans/presentation/shared/widgets/security/mfa_settings_card.dart';

import 'helpers/audit_test_helpers.dart';

/// `users-manage?fn=get-profile` na tugon para sa isang active na rider.
Map<String, dynamic> _profileResponse() => {
      'user': {
        'id': '22222222-2222-2222-2222-222222222222',
        'role': 'rider',
        'first_name': 'Jay',
        'middle_name': null,
        'last_name': 'Shin',
        'suffix': null,
        'email': 'jay@example.com',
        'phone_number': '09171234567',
        'account_status': 'active',
        'force_password_change': false,
        'profile_photo_url': null,
        'created_at': '2026-08-01T10:00:00.000Z',
        'last_login_at': '2026-09-27T10:00:00.000Z',
        'street_address': '12 Mabini St',
        'barangay': 'Poblacion',
        'city': 'Makati',
        'province': 'Metro Manila',
        'zip_code': '1210',
        'rider_profiles': {
          'vehicle_type': 'motorcycle',
          'plate_number': 'ABC 1234',
          'drivers_license_number': 'N01-23-456789',
          'vehicle_brand': 'honda',
        },
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
      initialLocation: '/rider/profile',
      routes: [
        GoRoute(
          path: '/rider/profile',
          builder: (_, __) => const RiderProfileScreen(),
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

  group('Rider profile desktop layout', () {
    testWidgets('1280px: dalawang column — kaliwang rail + mga section',
        (tester) async {
      await pumpProfile(tester, 1280);

      expect(find.byType(ModernProfileHeader), findsOneWidget);
      // Ang pangalan ay nasa header AT sa "Full name" row ng Personal Details.
      expect(find.text('Jay Shin'), findsWidgets);

      final header = tester.getTopLeft(find.byType(ModernProfileHeader));
      // `ModernSectionLabel` ay nag-uuppercase — "PERSONAL".
      final sections = tester.getTopLeft(find.text('PERSONAL'));

      // Magkatabi: nasa KANAN ng header ang mga section (hindi sa ilalim).
      expect(sections.dx, greaterThan(header.dx + 300),
          reason: 'Hindi magkatabi ang identity rail at ang mga section');
      expect((sections.dy - header.dy).abs(), lessThan(80),
          reason: 'Nasa ibaba (hindi katabi) ang mga section');

      // Nasa kaliwang rail din ang account actions (bersyon + Log Out).
      final logout = tester.getTopLeft(find.text('Log Out'));
      expect(logout.dx, lessThan(sections.dx));

      // 2FA (MFA) card sa Security — kapareho ng lender profile.
      expect(find.byType(MfaSettingsCard), findsOneWidget);
      expect(find.text('SECURITY'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('950px (katabi ng breakpoint): walang overflow',
        (tester) async {
      await pumpProfile(tester, 950);

      expect(find.byType(ModernProfileHeader), findsOneWidget);
      expect(find.text('PERSONAL'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final header = tester.getTopLeft(find.byType(ModernProfileHeader));
      final sections = tester.getTopLeft(find.text('PERSONAL'));
      expect(sections.dx, greaterThan(header.dx + 300));
    });

    testWidgets('390px: isang column pa rin (walang binago sa phone)',
        (tester) async {
      await pumpProfile(tester, 390);

      expect(find.byType(ModernProfileHeader), findsOneWidget);
      expect(find.byType(MfaSettingsCard), findsOneWidget);

      final header = tester.getTopLeft(find.byType(ModernProfileHeader));
      final sections = tester.getTopLeft(find.text('PERSONAL'));

      // Nasa IBABA ng header ang mga section — pareho ang kaliwang gilid.
      expect(sections.dy, greaterThan(header.dy),
          reason: 'Hindi na-stack ang mga section sa ilalim ng header');
      expect((sections.dx - header.dx).abs(), lessThan(24));
    });

    // Bagong behavior: text lang ang section titles. Walang rows sa ilalim —
    // ang mga field ay lumalabas sa POPUP at pwedeng i-edit doon.
    testWidgets('pag-pindot ng section title, bubukas ang editable popup',
        (tester) async {
      await pumpProfile(tester, 1280);

      // Walang inline na "Full name" row sa page bago pindutin.
      expect(find.text('Full name'), findsNothing);

      Future<void> openAndClose(
          String title, List<String> fields, List<String> values) async {
        await tester.tap(find.text(title));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        for (final f in fields) {
          expect(find.text(f), findsOneWidget,
              reason: 'Walang "$f" sa popup ng $title');
        }
        // Existing details: naka-prefill na dapat ang mga value.
        for (final v in values) {
          expect(find.text(v), findsOneWidget,
              reason: 'Walang existing value na "$v" sa popup ng $title');
        }
        expect(find.text('Save'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      await openAndClose('Personal Details',
          ['First Name', 'Phone Number', 'Member since'], ['Jay', '09171234567']);
      await openAndClose('Email', ['Email Address'], ['jay@example.com']);
      await openAndClose('Rider Information',
          ['Plate Number', "Driver's License Number", 'Vehicle Brand'],
          ['ABC 1234', 'N01-23-456789']);

      expect(find.text('Full name'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nakaka-save ng edit sa popup ng Personal Details',
        (tester) async {
      await pumpProfile(tester, 1280);

      await tester.tap(find.text('Personal Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Unang field = First Name.
      final fields = find.descendant(
          of: find.byType(Dialog), matching: find.byType(TextField));
      await tester.enterText(fields.first, 'Jayden');
      await tester.tap(find.text('Save'));
      // Ang save ay may async PATCH + reload — bigyan ng ilang frame.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      // Sarado na ang popup at may success feedback.
      expect(find.text('First Name'), findsNothing);
      expect(find.text('Personal details updated.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
