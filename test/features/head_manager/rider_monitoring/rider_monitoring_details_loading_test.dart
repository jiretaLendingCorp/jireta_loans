// test/features/head_manager/rider_monitoring/rider_monitoring_details_loading_test.dart
//
// REGRESSION: habang naglo-load pa lang ang rider details page, hubad na
// `Column` (fixed-height shimmer) ang body nito — sumobra ito sa mababang
// viewport at lumabas ang "BOTTOM OVERFLOWED BY N PIXELS" sa ilalim ng page.
// Sinusuri dito na scrollable ang skeleton at walang overflow kahit 1366x587
// lang (1366x690 desktop minus ang 64px top bar at browser chrome) o mas
// mababa pa.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/presentation/features/head_manager/rider_monitoring/screens/hm_rider_monitoring_details_screen.dart';

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(
      body: RiderMonitoringDetailSkeleton(),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('walang overflow sa 1366x587 na viewport', (tester) async {
    await _pumpAt(tester, const Size(1366, 587));

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('naka-scroll pa rin kahit mas mababa ang viewport',
      (tester) async {
    await _pumpAt(tester, const Size(1366, 400));

    expect(tester.takeException(), isNull);

    // Sulit ang scroll: umaabot pa sa ibaba ang natitirang shimmer.
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
