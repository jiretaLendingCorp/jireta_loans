// test/reset_mfa_dialog_test.dart
//
// Ang confirm step ng Head Manager-assisted 2FA reset (lender / rider).
// Sinusuri lang nito ang UI: may confirmation BAGO tumawag sa server, at
// nakasaad kung kaninong account ang mababago. Ang tunay na hangganan ay
// server-side (`users-admin?fn=reset-mfa`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/shared/widgets/security/reset_mfa_dialog.dart';

void main() {
  testWidgets('hihingi muna ng confirmation bago i-reset ang 2FA',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => confirmAndResetMfa(
                context,
                userId: 'u-1',
                personName: 'Maria Santos',
                roleLabel: 'lender',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Reset 2FA?'), findsOneWidget);
    expect(find.textContaining('Maria Santos (lender)'), findsOneWidget);
    expect(find.text('Reset 2FA'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Cancel = walang request na nangyayari.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Reset 2FA?'), findsNothing);
  });
}
