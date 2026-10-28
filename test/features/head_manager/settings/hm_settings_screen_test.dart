// test/features/head_manager/settings/hm_settings_screen_test.dart
//
// Ang System Settings page ay dapat laman lang ng SYSTEM CONFIG (ang dating
// Roles & Permissions / SMS Templates / Report Templates tabs ay tinanggal),
// at ang Interest Rate field ay nagpapakita ng aktwal na value na itinakda ng
// Head Manager. Naka-lock naman ang Penalty Rate sa 20%.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jireta_loans/presentation/features/head_manager/settings/providers/hm_settings_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/settings/screens/hm_settings_screen.dart';

Future<void> pumpSettings(
  WidgetTester tester, {
  String interestRate = '30',
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/hm/settings',
    routes: [
      GoRoute(
        path: '/hm/settings',
        builder: (_, __) => const HmSettingsScreen(),
      ),
      GoRoute(
        path: '/hm/dashboard',
        builder: (_, __) => const Scaffold(body: SizedBox()),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Hindi na kailangan ng DI/network dito — canned config lang.
        systemConfigProvider.overrideWith((ref) async => [
              {'config_key': 'interest_rate', 'config_value': interestRate},
              {'config_key': 'penalty_rate', 'config_value': '20'},
            ]),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

TextField fieldFor(WidgetTester tester, String label) {
  final row = find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first;
  return tester.widget<TextField>(
    find.descendant(of: row, matching: find.byType(TextField)),
  );
}

void main() {
  testWidgets('System Config lang ang laman ng System Settings page',
      (tester) async {
    await pumpSettings(tester);
    expect(tester.takeException(), isNull);

    // Tinanggal na ang dating tabs.
    expect(find.text('Roles & Permissions'), findsNothing);
    expect(find.text('SMS Templates'), findsNothing);
    expect(find.text('Report Templates'), findsNothing);

    // Nakatago na ang "System Configuration" section header.
    expect(find.text('System Configuration'), findsNothing);

    // Ang settings fields mismo ang narito.
    expect(find.text('Interest Rate (%)'), findsOneWidget);
    expect(find.text('Minimum Loan Amount (₱)'), findsOneWidget);

    // Naka-format nang may thousand separator ang money fields.
    expect(
      fieldFor(tester, 'Minimum Loan Amount (₱)').controller?.text,
      '3,000',
    );

    // "Settings" (hindi "System Settings") ang title ng page.
    expect(find.text('System Settings'), findsNothing);
    expect(find.text('Settings'), findsWidgets);

    // Nakatagong auth/security fields (OTP, login, lockout, session).
    expect(find.text('OTP Expiry (minutes)'), findsNothing);
    expect(find.text('Max Login Attempts'), findsNothing);
    expect(find.text('Account Lockout (minutes)'), findsNothing);
    expect(find.text('Session Timeout (minutes)'), findsNothing);
  });

  testWidgets('ipakita ang 30% na nakatakda ng Head Manager', (tester) async {
    await pumpSettings(tester, interestRate: '30');
    expect(fieldFor(tester, 'Interest Rate (%)').controller?.text, '30');
  });

  testWidgets('ipakita ang 20% na nakatakda ng Head Manager', (tester) async {
    await pumpSettings(tester, interestRate: '20');
    expect(fieldFor(tester, 'Interest Rate (%)').controller?.text, '20');
  });

  testWidgets('naka-lock ang penalty rate sa 20%', (tester) async {
    await pumpSettings(tester, interestRate: '30');

    final penalty = fieldFor(tester, 'Penalty Rate (%)');
    expect(penalty.enabled, isFalse);
    expect(penalty.controller?.text, '20');
  });
}
