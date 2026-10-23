// test/web_auth_footer_terms_test.dart
//
// TERMS & CONDITIONS SA FOOTER NG WEB LOGIN (/login, /register)
//
// Dati, isang talata lang ang lumalabas kapag pinindot ang "Terms & Conditions"
// sa Explore ng footer ("By accessing the Jireta staff portal, you agree…").
// Ngayon, ang BUONG T&C ang binubuksan — kaparehong nilalaman ng profile at ng
// loan-apply wizard ([kTermsAndConditionsSections]).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/presentation/shared/widgets/layout/web_auth_footer.dart';

void main() {
  testWidgets('footer: buong Terms & Conditions ang binubuksan', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: WebAuthFooter()),
      ),
    ));
    // Fade-in ng footer (320ms delay + 520ms animation).
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Terms & Conditions'));
    await tester.pumpAndSettle();

    // Simula ng T&C — hindi na ang dating isang-talatang staff-portal notice.
    expect(find.text('Introduction'), findsOneWidget);
    expect(find.text('1. Account Security'), findsOneWidget);
    expect(
        find.textContaining('By accessing and using the Jireta Loans & Credit'),
        findsOneWidget);

    // Dulo ng T&C — kailangang i-scroll (mahabang nilalaman).
    await tester.scrollUntilVisible(
      find.text('Sta. Barbara, Pangasinan'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('7. Agreement and Acceptance'), findsOneWidget);
    expect(find.text('Jireta Loans & Credit Corp.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('footer: buong Privacy Policy ang binubuksan', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: WebAuthFooter()),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Privacy Policy'));
    await tester.pumpAndSettle();

    expect(find.text('1. Introduction'), findsOneWidget);
    expect(find.text('2. Information We Collect'), findsOneWidget);
    expect(
        find.textContaining('respects the privacy of its lenders, employees'),
        findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('13. Acknowledgment'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('12. Contact Information and Privacy Concerns'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
