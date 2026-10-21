// test/features/head_manager/rider_quotas/rider_quota_table_layout_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/models/rider_quota_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_quotas/providers/hm_rider_quotas_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_quotas/screens/hm_rider_quotas_screen.dart';

const _quota = RiderQuota(
  quotaId: 'q1',
  riderId: 'r1',
  riderName: 'Anthony Maramba',
  phoneNumber: '09635267491',
  period: RiderQuotaPeriod.daily,
  targetAmount: 10000,
  confirmedCollection: 7500.5,
  remainingTarget: 2499.5,
  completionPercentage: 75.01,
  status: RiderQuotaStatus.active,
  isActive: true,
  paymentCount: 3,
);

Widget _host(double width, {double height = 420}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: RiderQuotaTable(
              state: const HmRiderQuotasState(
                rows: [_quota],
                total: 1,
              ),
              onEdit: (_) {},
              onClose: (_) {},
            ),
          ),
        ),
      ),
    );

void main() {
  // REGRESSION: 1366px screen → ~1060px content area pagkatapos ng sidebar at
  // padding. Dapat TABULAR pa rin doon (hindi stacked cards).
  testWidgets('desktop content width (1062px) ay tabular at tama ang halaga',
      (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(1062));
    await tester.pumpAndSettle();

    // Desktop header labels (uppercase, walang ":")
    expect(find.text('RIDER'), findsOneWidget);
    expect(find.text('QUOTA'), findsOneWidget);
    expect(find.text('CONFIRMED'), findsOneWidget);
    expect(find.text('PROGRESS'), findsOneWidget);
    expect(find.text('STATUS'), findsOneWidget);
    expect(find.text('ACTIONS'), findsOneWidget);
    expect(find.text('RIDER:'), findsNothing);

    expect(find.text('Anthony Maramba'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('₱10,000.00'), findsOneWidget);
    expect(find.text('₱7,500.50'), findsOneWidget);
    expect(find.text('₱2,499.50'), findsOneWidget);
    expect(find.text('75.0%'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);

    // Action buttons dapat naroon sa desktop (hindi blangkong ACTIONS column).
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
  });

  testWidgets('maliit na width ay stacked cards pa rin', (tester) async {
    await tester.pumpWidget(_host(640, height: 900));
    await tester.pumpAndSettle();

    expect(find.text('RIDER:'), findsOneWidget);
    expect(find.text('Anthony Maramba'), findsOneWidget);
    expect(find.text('75.0%'), findsOneWidget);
    // Hindi rin dapat mawala ang actions sa stacked-card layout.
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });
}
