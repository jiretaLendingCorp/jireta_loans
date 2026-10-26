// test/privacy_policy_screen_test.dart
//
// Public na `/privacy-policy` page: dapat may AKTWAL na nilalaman (hindi lang
// app shell) dahil ito ang ginagamit na "Application privacy policy link" sa
// Google OAuth verification at sa mga external na link. May back button din
// para makalabas ang user pabalik sa login page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/presentation/features/auth/screens/privacy_policy_screen.dart';

void main() {
  testWidgets('privacy policy page: buo ang nilalaman, walang login',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyScreen()));

    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('1. Introduction'), findsOneWidget);
    expect(
      find.textContaining('Jireta Loans & Credit Corp. respects the privacy'),
      findsOneWidget,
      reason: 'Walang aktwal na privacy content sa page',
    );
  });

  /// Router na may login page (stub) at ang public privacy page — pareho ng
  /// hugis ng tunay na app: `/login` at `/mobile-login` ang pinanggagalingan
  /// ng mga legal link sa footer.
  GoRouter buildRouter({String initialLocation = '/privacy-policy'}) {
    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/privacy-policy',
          builder: (_, __) => const PrivacyPolicyScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('WEB LOGIN')),
        ),
        GoRoute(
          path: '/mobile-login',
          builder: (_, __) => const Scaffold(body: Text('MOBILE LOGIN')),
        ),
      ],
    );
  }

  testWidgets('back button: nasa page at bumabalik sa login kapag walang history',
      (tester) async {
    // Direktang bukas ang URL (bagong tab / refresh) — walang ma-po-pop, kaya
    // sa login page ng platform babalik. Sa VM tests, kIsWeb = false.
    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('legalBackButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('legalBackButton')));
    await tester.pumpAndSettle();

    expect(find.text('MOBILE LOGIN'), findsOneWidget);
  });

  testWidgets('back button: pum-pop pabalik sa pinanggalingang page',
      (tester) async {
    final router = buildRouter(initialLocation: '/login');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.push('/privacy-policy');
    await tester.pumpAndSettle();
    expect(find.text('Privacy Policy'), findsOneWidget);

    await tester.tap(find.byKey(const Key('legalBackButton')));
    await tester.pumpAndSettle();

    expect(find.text('WEB LOGIN'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsNothing);
  });
}
