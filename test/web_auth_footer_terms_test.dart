// test/web_auth_footer_terms_test.dart
//
// PRIVACY POLICY AT TERMS & CONDITIONS SA FOOTER NG WEB LOGIN (/login, /register)
//
// Dati, bottom sheet ang binubuksan ng dalawang link sa Explore ng footer —
// walang sariling address. Ngayon, may TOTOONG URI ang dalawa gaya ng mga link
// sa login page: `/privacy-policy` at `/terms-and-conditions` — kaya may
// maibabahagi/bookmark na link at magagamit sa Google OAuth verification.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/core/constants/route_constants.dart';
import 'package:jireta_loans/presentation/features/auth/screens/privacy_policy_screen.dart';
import 'package:jireta_loans/presentation/features/auth/screens/terms_of_service_screen.dart';
import 'package:jireta_loans/presentation/shared/widgets/layout/web_auth_footer.dart';

/// Maliit na router na may parehong URI ng totoong app, para masukat ang
/// aktwal na pupuntahan ng link.
GoRouter _router() {
  return GoRouter(
    initialLocation: RouteConstants.webLogin,
    routes: [
      GoRoute(
        path: RouteConstants.webLogin,
        builder: (_, __) => const Scaffold(
          body: SingleChildScrollView(child: WebAuthFooter()),
        ),
      ),
      GoRoute(
        path: RouteConstants.privacyPolicy,
        builder: (_, __) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: RouteConstants.termsAndConditions,
        builder: (_, __) => const TermsOfServiceScreen(),
      ),
    ],
  );
}

Future<GoRouter> _pumpFooter(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = _router();
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  // Fade-in ng footer (320ms delay + 520ms animation).
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('footer: Privacy Policy ay may sariling URI', (tester) async {
    final router = await _pumpFooter(tester, const Size(1280, 900));

    await tester.tap(find.text('Privacy Policy'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, RouteConstants.privacyPolicy);
    expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
    expect(find.text('1. Introduction'), findsOneWidget);
    expect(
        find.textContaining('respects the privacy of its lenders, employees'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('footer: Terms & Conditions ay may sariling URI', (tester) async {
    final router = await _pumpFooter(tester, const Size(1280, 900));

    await tester.tap(find.text('Terms & Conditions'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, RouteConstants.termsAndConditions);
    expect(find.byType(TermsOfServiceScreen), findsOneWidget);
    expect(find.text('Introduction'), findsOneWidget);
    expect(
        find.textContaining('By accessing and using the Jireta Loans & Credit'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact footer: pareho rin ang URI (mobile web)',
      (tester) async {
    final router = await _pumpFooter(tester, const Size(600, 900));

    await tester.tap(find.text('Terms & Conditions'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, RouteConstants.termsAndConditions);
    expect(find.byType(TermsOfServiceScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
