// test/features/rider/collections/rider_collection_summary_header_test.dart
//
// Ang summary header ay read-only: expected (total due), confirmed
// (verified only) at remaining, plus overdue follow-up. Sinusuri dito na
// eksaktong piso ang display, lumalabas ang overdue warning, at gumagana ang
// "Today" filter at retry.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/models/rider_collection_monitoring_model.dart';
import 'package:jireta_loans/presentation/features/rider/collections/providers/rider_collection_summary_provider.dart';
import 'package:jireta_loans/presentation/features/rider/collections/widgets/rider_collection_summary_header.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows exact expected, confirmed at remaining amounts',
      (tester) async {
    var today = false;
    await tester.pumpWidget(wrap(RiderCollectionSummaryHeader(
      state: const RiderCollectionSummaryState(
        summary: RiderMonitoringSummary(
          expectedCollection: 12500,
          confirmedCollection: 3200.5,
          remainingDue: 9299.5,
          overdueAccounts: 1,
          overdueInstallments: 2,
        ),
      ),
      onRetry: () {},
      todayOnly: today,
      onTodayChanged: (v) => today = v,
    )));

    expect(find.text('₱12,500.00'), findsOneWidget);
    expect(find.text('₱3,200.50'), findsOneWidget);
    expect(find.text('₱9,299.50'), findsOneWidget);
    expect(
      find.textContaining('1 overdue account(s)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('2 installment(s) need follow-up'),
      findsOneWidget,
    );

    await tester.tap(find.text('Today'));
    expect(today, isTrue);
  });

  testWidgets('walang overdue warning kapag zero ang overdue',
      (tester) async {
    await tester.pumpWidget(wrap(RiderCollectionSummaryHeader(
      state: const RiderCollectionSummaryState(
        summary: RiderMonitoringSummary(
          expectedCollection: 500,
          confirmedCollection: 500,
          remainingDue: 0,
        ),
      ),
      onRetry: () {},
      todayOnly: false,
      onTodayChanged: (_) {},
    )));

    expect(find.textContaining('overdue account'), findsNothing);
    expect(find.text('₱500.00'), findsNWidgets(2));
    expect(find.text('₱0.00'), findsOneWidget);
  });

  testWidgets('error state shows message at retry action', (tester) async {
    var retried = false;
    await tester.pumpWidget(wrap(RiderCollectionSummaryHeader(
      state: const RiderCollectionSummaryState(
        error: 'Failed to load collection summary',
      ),
      onRetry: () => retried = true,
      todayOnly: false,
      onTodayChanged: (_) {},
    )));

    expect(find.text('Failed to load collection summary'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
