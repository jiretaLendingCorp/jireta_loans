import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/features/head_manager/loans/widgets/loan_reapply_picker.dart';

Future<void> pumpPicker(
  WidgetTester tester,
  ValueChanged<LoanReapplyChoice?> onChanged,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LoanReapplyPicker(onChanged: onChanged),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('walang default — hindi ito basta 1 month', (tester) async {
    final choices = <LoanReapplyChoice?>[];
    await pumpPicker(tester, choices.add);

    expect(choices, isEmpty);
    expect(
      find.text('No default — choose when the lender can apply again.'),
      findsOneWidget,
    );
  });

  testWidgets('Permanent reject → permanent, walang petsa', (tester) async {
    final choices = <LoanReapplyChoice?>[];
    await pumpPicker(tester, choices.add);

    expect(find.text('Permanent reject'), findsOneWidget);
    await tester.tap(find.text('Permanent reject'));
    await tester.pumpAndSettle();

    expect(choices, hasLength(1));
    expect(choices.last!.permanent, isTrue);
    expect(choices.last!.allowedAt, isNull);
    expect(find.textContaining('Permanent:'), findsOneWidget);
  });

  testWidgets('1 month → petsa mga isang buwan mula ngayon', (tester) async {
    final choices = <LoanReapplyChoice?>[];
    await pumpPicker(tester, choices.add);

    await tester.tap(find.text('1 month'));
    await tester.pumpAndSettle();

    final choice = choices.last!;
    expect(choice.permanent, isFalse);
    expect(choice.allowedAt, isNotNull);
    final daysAhead = choice.allowedAt!.difference(DateTime.now()).inDays;
    expect(daysAhead, inInclusiveRange(27, 32));
  });

  testWidgets('Immediately → pwede agad (date ngayon)', (tester) async {
    final choices = <LoanReapplyChoice?>[];
    await pumpPicker(tester, choices.add);

    await tester.tap(find.text('Immediately'));
    await tester.pumpAndSettle();

    final choice = choices.last!;
    expect(choice.permanent, isFalse);
    expect(choice.allowedAt!.difference(DateTime.now()).inSeconds.abs(), lessThan(5));
    expect(find.text('The lender can apply again right away.'), findsOneWidget);
  });
}
