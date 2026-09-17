// test/in_office_validation_autohide_test.dart
//
// VALIDATION ERROR SA "Lender Account Upgrade" WIZARD (walk-in / in-office)
//
// GINUSTO: kapag pinindot ang Next na may kulang na field, ang error text
// ("This field is required") ay 2 SEGUNDO lang dapat nakikita — hindi ito
// manatili at "naka-stack" pataas ang buong form.
//
// MAHALAGA: hindi dapat humina ang validation — kahit nakatago na ang error,
// ang `Form.validate()` pa rin ang humaharang sa Next. Sinusuri ng test na
// ito ang dalawang bagay:
//   1. Ang error text ay lumalabas pagkatapos ng Next at nawawala pagkatapos
//      ng 2 segundo.
//   2. Hindi pa rin tumutuloy sa Address step ang invalid na form.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/features/head_manager/in_office/widgets/in_office_wizard.dart';

const _errorText = 'This field is required';

Future<void> _pumpWizard(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          // Walang applicationId → hindi nagre-request sa backend, at nasa
          // unang step (Identify) agad.
          child: InOfficeWizard(applicationId: null, onComplete: () {}),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wala pang error text sa umpisa', (tester) async {
    await _pumpWizard(tester);
    expect(find.text(_errorText), findsNothing);
  });

  testWidgets('lumalabas ang error pagkatapos ng Next, 2s lang nakikita',
      (tester) async {
    await _pumpWizard(tester);

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text(_errorText), findsWidgets,
        reason: 'dapat may error text agad pagkatapos tap ng Next');

    // 1 segundo pa — nandiyan pa ang error.
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text(_errorText), findsWidgets);

    // Lumipas na ang 2 segundo — nawawala na lahat ng error text.
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    expect(find.text(_errorText), findsNothing,
        reason: 'dapat auto-hide ang error text pagkatapos ng 2 segundo');
  });

  testWidgets('hindi tumutuloy sa Address step ang invalid na form',
      (tester) async {
    await _pumpWizard(tester);

    await tester.tap(find.text('Next'));
    // Tapos na ang 2-second window — nakatago na ang error text...
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // ...pero nasa step 1 (Identify) pa rin: hindi lumitaw ang Address fields.
    expect(find.text('Street / House No.'), findsNothing);
    expect(find.text('Phone Number'), findsOneWidget);
  });
}
