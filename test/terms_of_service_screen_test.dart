// test/terms_of_service_screen_test.dart
//
// Public na `/terms-and-conditions` page: parehong design at nilalaman ng
// Privacy Policy page, at may aktwal na T&C text (hindi lang app shell) dahil
// ito ang binubuksan ng "Terms & Conditions" link sa login page at magagamit
// sa Google OAuth verification.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/presentation/features/auth/screens/terms_of_service_screen.dart';

void main() {
  testWidgets('terms page: buo ang nilalaman, walang login', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TermsOfServiceScreen()));

    expect(find.text('Terms & Conditions'), findsOneWidget);
    expect(find.text('Introduction'), findsOneWidget);
    expect(
      find.textContaining('By accessing and using the Jireta Loans'),
      findsOneWidget,
      reason: 'Walang aktwal na T&C content sa page',
    );
  });
}
