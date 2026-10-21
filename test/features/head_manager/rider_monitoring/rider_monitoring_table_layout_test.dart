// test/features/head_manager/rider_monitoring/rider_monitoring_table_layout_test.dart
//
// REGRESSION: sa 1366px desktop (~1060px content pagkatapos ng sidebar at
// padding) ay lumalabas ang stacked-card layout — napakataas ng bawat rider at
// hindi tabular. Ang dahilan ay `minTableWidth` na mas mataas sa available
// width. Sinusuri dito na:
//   • desktop width → tabular headers (RIDER, ACCOUNTS, …)
//   • maliit na width → card layout pa rin (RIDER:) para mobile-safe
//   • buo ang lahat ng header — dating "ACTI…" lang ang Actions (flex 1)
//   • naka-cap sa 100% ang performance (dati 166.7%)
//
// TOTOONG Inter font ang ginagamit: ang default test font (Ahem) ay sobrang
// lapad, kaya nagmumukhang napuputol ang mga header kahit maayos naman ito sa
// app.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/models/rider_collection_monitoring_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_monitoring/providers/hm_rider_monitoring_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_monitoring/screens/hm_rider_monitoring_screen.dart';

const _row = RiderMonitoringRow(
  riderId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  riderName: 'Anthony Maramba',
  phoneNumber: '09635267491',
  plateNumber: 'PRT-6817',
  assignedAccounts: 4,
  assignedInstallments: 6,
  expectedCollection: 12000,
  confirmedCollection: 7500.5,
  remainingDue: 4499.5,
  overdueAccounts: 2,
  lastActivityAt: null,
  collectionPerformance: 62.5,
);

Future<void> _loadInterFont() async {
  final loader = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes =
        File('assets/fonts/Inter/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Widget _host(
  double width,
  List<RiderMonitoringRow> rows, {
  double height = 320,
}) =>
    MaterialApp(
      theme: ThemeData(useMaterial3: true, fontFamily: 'Inter'),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: RiderMonitoringTable(
              state: HmRiderMonitoringState(
                rows: rows,
                total: rows.length,
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(_loadInterFont);

  testWidgets('desktop width ay tabular, hindi stacked cards', (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(1062, const [_row]));
    await tester.pumpAndSettle();

    // Desktop header labels (uppercase, walang ":") mula sa ResponsiveListCard.
    expect(find.text('RIDER'), findsOneWidget);
    expect(find.text('ACCOUNTS'), findsOneWidget);
    expect(find.text('ACTIVITY'), findsOneWidget);
    expect(find.text('PERFORMANCE'), findsOneWidget);
    // Hindi ito ang mobile card labels.
    expect(find.text('RIDER:'), findsNothing);

    // REGRESSION: dating "ACTI…" lang ang header ng Actions dahil flex 1
    // lang ito. Dapat buo ang lahat ng header sa 1366px desktop.
    for (final label in [
      'ACCOUNTS',
      'ACTIVITY',
      'PERFORMANCE',
      'ACTIONS',
    ]) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(label),
      );
      expect(paragraph.didExceedMaxLines, isFalse,
          reason: 'Naputol ang "$label" header sa 1062px width');
    }

    expect(find.text('Anthony Maramba'), findsOneWidget);
    expect(find.text('₱12,000.00'), findsOneWidget);
    expect(find.text('₱7,500.50'), findsOneWidget);
    expect(find.text('62.5%'), findsOneWidget);
  });

  testWidgets('performance ay naka-cap sa 100%', (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const overCollected = RiderMonitoringRow(
      riderId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      riderName: 'Daniel Ferer',
      assignedAccounts: 1,
      expectedCollection: 6300,
      confirmedCollection: 10500,
      collectionPerformance: 166.7,
    );

    await tester.pumpWidget(_host(1062, const [overCollected]));
    await tester.pumpAndSettle();

    // Hindi na lumalabas ang 166.7% — 100% ang cap ng display.
    expect(find.text('100.0%'), findsOneWidget);
    expect(find.text('166.7%'), findsNothing);
  });

  testWidgets('maliit na width ay card layout pa rin', (tester) async {
    // Sapat ang taas para sa stacked card; sa app ay nasa scroll view ito.
    await tester.pumpWidget(_host(600, const [_row], height: 1200));
    await tester.pumpAndSettle();

    expect(find.text('RIDER:'), findsOneWidget);
    expect(find.text('Anthony Maramba'), findsOneWidget);
  });
}
