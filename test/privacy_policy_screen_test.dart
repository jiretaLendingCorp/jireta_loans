// test/privacy_policy_screen_test.dart
//
// Public na `/privacy-policy` page: dapat may AKTWAL na nilalaman (hindi lang
// app shell) dahil ito ang ginagamit na "Application privacy policy link" sa
// Google OAuth verification at sa mga external na link.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
