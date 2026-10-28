// test/lender_profile_desktop_test.dart
//
// DESKTOP LAYOUT NG LENDER PROFILE (/lender/profile)
//
// Dati, isang column lang ang profile kahit sa desktop — kaya nakaunat ang
// mobile na ayos sa buong browser. Mula sa [kDesktopBreakpoint] pataas:
//
//   * kaliwang rail (360px): identity (avatar / pangalan / status) + bersyon;
//     walang Log out dito — nasa sidebar na ito sa desktop;
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

import 'package:jireta_loans/core/constants/app_constants.dart';
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

      // Nasa kaliwang rail ang bersyon, pero WALANG Log out button dito sa
      // desktop — may "Log Out" na sa sidebar.
      final version = tester.getTopLeft(find.textContaining('Version '));
      expect(version.dx, lessThan(sections.dx));
      expect(find.text('Log out'), findsNothing);
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

    // Help Center: pantay ang icon at text column ng Chat, email, at numero —
    // dating pill button ang Chat kaya hindi naka-line up sa dalawang linya.
    testWidgets('Help Center: pantay ang Chat, email, at numero',
        (tester) async {
      await pumpProfile(tester, 1280);

      // Nasa ibaba ng profile ang Help Center — i-scroll muna bago pindutin.
      await tester.ensureVisible(find.text('Help Center'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Help Center'));
      await tester.pumpAndSettle();

      expect(find.text('Frequently Asked Questions'), findsNothing);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.text(AppConstants.supportEmail), findsOneWidget);
      expect(find.text(AppConstants.supportPhone), findsOneWidget);

      // Chat ay hindi pa available — walang onTap (disabled).
      final chat = tester.widget<InkWell>(
        find
            .ancestor(of: find.text('Chat'), matching: find.byType(InkWell))
            .first,
      );
      expect(chat.onTap, isNull);

      final chatIconX =
          tester.getTopLeft(find.byIcon(Icons.chat_bubble_outline_rounded)).dx;
      final mailIconX =
          tester.getTopLeft(find.byIcon(Icons.mail_outline_rounded)).dx;
      final phoneIconX =
          tester.getTopLeft(find.byIcon(Icons.phone_outlined)).dx;
      expect(mailIconX, closeTo(chatIconX, 0.5));
      expect(phoneIconX, closeTo(chatIconX, 0.5));

      final chatTextX = tester.getTopLeft(find.text('Chat')).dx;
      final mailTextX =
          tester.getTopLeft(find.text(AppConstants.supportEmail)).dx;
      final phoneTextX =
          tester.getTopLeft(find.text(AppConstants.supportPhone)).dx;
      expect(mailTextX, closeTo(chatTextX, 0.5));
      expect(phoneTextX, closeTo(chatTextX, 0.5));

      expect(tester.takeException(), isNull);
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

    // REGRESSION: flat na row pero WALANG icon — plain text lang ang lahat ng
    // item ("Personal Details", "Push Notifications", "Terms & Conditions"…),
    // mahirap i-scan. Dapat may icon ang bawat item.
    testWidgets('may icon ang bawat item sa profile', (tester) async {
      await pumpProfile(tester, 1280);

      for (final icon in const [
        Icons.person_outline_rounded, // Personal Details
        Icons.email_outlined, // Email
        Icons.location_on_outlined, // Residence Address
        Icons.notifications_active_outlined, // Push Notifications
        Icons.lock_outline_rounded, // Change/ Set MPIN
        Icons.description_outlined, // Terms & Conditions
        Icons.privacy_tip_outlined, // Privacy Policy
        Icons.support_agent_outlined, // Help Center
      ]) {
        expect(find.byIcon(icon), findsWidgets,
            reason: 'Walang icon ($icon) sa profile item');
      }
      expect(tester.takeException(), isNull);
    });

    // Text lang ang section titles — walang card at walang arrow. Bubukas ang
    // popup na may EXISTING details at pwedeng i-edit.
    testWidgets('pag-pindot ng section title, bubukas ang editable popup',
        (tester) async {
      await pumpProfile(tester, 1280);

      Future<void> openAndClose(
          String title, List<String> fields, List<String> values) async {
        await tester.tap(find.text(title));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        for (final f in fields) {
          expect(find.text(f), findsOneWidget,
              reason: 'Walang "$f" sa popup ng $title');
        }
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
          ['First Name', 'Gender', 'Date of Birth'], ['Blake', 'Male']);
      await openAndClose('Email', ['Email Address'], ['blake@example.com']);
      await openAndClose(
          'Residence Address',
          ['Street Address', 'Barangay', 'City / Municipality'],
          ['12 Mabini St', 'Poblacion', 'Makati']);

      expect(tester.takeException(), isNull);
    });
  });
}
