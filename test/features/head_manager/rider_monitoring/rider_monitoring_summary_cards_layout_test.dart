// test/features/head_manager/rider_monitoring/rider_monitoring_summary_cards_layout_test.dart
//
// REGRESSION: dating tatlong napakalaki at naka-stretch na card kada row ang
// summary — halos kalahati ng viewport ang nauubos bago pa makarating sa
// monitoring table. Sinusuri dito na anim na compact card ang magkasya sa
// isang row sa desktop at hindi ito naka-stretch sa buong content width.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/models/rider_collection_monitoring_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_monitoring/screens/hm_rider_monitoring_screen.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_monitoring/widgets/rider_monitoring_stat_card.dart';

const _summary = RiderMonitoringSummary(
  activeRiders: 8,
  assignedAccounts: 4,
  assignedInstallments: 6,
  expectedCollection: 96922,
  confirmedCollection: 100922,
  remainingDue: 0,
  overdueAccounts: 0,
  overdueInstallments: 0,
  openAssignments: 0,
  confirmedPayments: 9,
  collectionPerformance: 104.1,
);

void main() {
  testWidgets('anim na compact card sa isang row sa desktop',
      (tester) async {
    // Kailangan ng totoong desktop surface; kapag 800px lang ang test surface,
    // pinuputol ng Center ang 1062px na SizedBox kaya 3-per-row ang susukatin.
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 1062,
            child: RiderMonitoringSummaryCards(summary: _summary),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(RiderMonitoringStatCard), findsNWidgets(6));
    expect(find.text('Total Active Riders'), findsOneWidget);
    expect(find.text('Remaining Amount Due'), findsOneWidget);

    // Isang row lang: hindi lalampas sa ~130px ang buong block.
    final size = tester.getSize(find.byType(RiderMonitoringSummaryCards));
    expect(size.height, lessThanOrEqualTo(130));

    // Hindi naka-stretch: bawat card ay mas maliit sa kalahati ng content.
    final card = tester.getSize(find.byType(RiderMonitoringStatCard).first);
    expect(card.width, lessThan(1062 / 4));
  });

  testWidgets('tablet width ay 3 kada row, walang overflow', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 780,
            child: RiderMonitoringSummaryCards(summary: _summary),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(RiderMonitoringStatCard), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });
}
