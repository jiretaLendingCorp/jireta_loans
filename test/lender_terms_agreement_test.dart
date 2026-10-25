// test/lender_terms_agreement_test.dart
//
// TERMS AND CONDITIONS (2-step re-apply)
//
// ANO ANG TINITIGNAN NITO
//   • Visible ang Terms and Conditions checkbox kapag may previous loan
//     (quick re-apply flow), at required ito bago ang Submit Application.
//   • Nagto-toggle ang checkbox at nagbubukas ng T&C sheet ang link.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/presentation/features/lender/loans/screens/lender_apply_loan_screen.dart';

String _readNormalized(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

Widget _host(ValueNotifier<bool> value) => MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Padding(
            padding: const EdgeInsets.all(16),
            child: LenderTermsAgreementCheckbox(
              value: value.value,
              onChanged: (v) {
                value.value = v;
                setState(() {});
              },
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('checkbox: naka-uncheck sa umpisa, nagti-toggle kapag pinindot',
      (tester) async {
    final value = ValueNotifier<bool>(false);
    addTearDown(value.dispose);

    await tester.pumpWidget(_host(value));

    // May text sa itaas ng checkbox — gaya ng unang loan application.
    expect(
      find.textContaining('I confirm that the information in this loan application'),
      findsOneWidget,
    );
    expect(find.text('I have read and agree to the '), findsOneWidget);
    expect(find.text('Terms and Conditions'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    expect(value.value, isTrue);

    await tester.tap(find.text('I have read and agree to the '));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets('link: binubuksan ang buong T&C sheet', (tester) async {
    final value = ValueNotifier<bool>(false);
    addTearDown(value.dispose);

    await tester.pumpWidget(_host(value));

    await tester.tap(find.text('Terms and Conditions'));
    await tester.pumpAndSettle();

    // LegalInfoSheet title ng T&C.
    expect(find.text('Terms & Conditions'), findsOneWidget);
    // KAPAREHO ng unang loan application ang nilalaman — may pamagat na
    // "JIRETA LOANS & CREDIT CORP." / "Loan Amount, Payment, and Process
    // Confirmation", tapos 1. Loan Amount. Walang "Introduction" at wala
    // ang account-level T&C ("1. Account Security") ng profile/footer.
    expect(find.text('Introduction'), findsNothing);
    expect(find.text('JIRETA LOANS & CREDIT CORP.'), findsOneWidget);
    expect(
      find.text('Loan Amount, Payment, and Process Confirmation'),
      findsOneWidget,
    );
    expect(find.text('1. Loan Amount'), findsOneWidget);
    expect(find.text('11. Electronic Confirmation'), findsOneWidget);
    expect(find.text('1. Account Security'), findsNothing);
    // Hindi na-tick ang checkbox sa pagbukas ng link.
    expect(value.value, isFalse);
  });

  group('Source guard: required bago ang quick re-apply submit', () {
    late String src;

    setUpAll(() {
      src = _readNormalized(
          'lib/presentation/features/lender/loans/screens/lender_apply_loan_screen.dart');
    });

    test('visible ang terms sa 2-step re-apply, bago ang Submit nav', () {
      final quickStart = src.indexOf('Widget _buildQuickApplyContent(');
      final quickEnd = src.indexOf('Widget _buildQuickHeader(');
      expect(quickStart, greaterThan(-1));
      expect(quickEnd, greaterThan(quickStart));
      final quick = src.substring(quickStart, quickEnd);

      final terms = quick.indexOf('_buildTermsAgreement()');
      final nav = quick.indexOf('_buildQuickStepNav(isSubmitting)');
      expect(terms, greaterThan(-1), reason: 'nakalabas ang T&C checkbox');
      expect(nav, greaterThan(terms), reason: 'nasa itaas ito ng Submit row');
    });

    test('hindi makakapag-submit kapag hindi naka-check', () {
      final start = src.indexOf('Future<void> _submitQuickApply(');
      final end = src.indexOf('Future<bool> _confirmAndAuthenticate(');
      final quick = src.substring(start, end);

      expect(quick, contains('if (!_acceptedTerms)'));
      expect(quick, contains('Please agree to the Terms and Conditions'));
      // Bago pa man humingi ng confirm/auth, hinarang na ang submit.
      expect(quick.indexOf('if (!_acceptedTerms)'),
          lessThan(quick.indexOf('_confirmAndAuthenticate()')));
    });
  });
}
