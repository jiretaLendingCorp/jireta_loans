// test/features/head_manager/rider_monitoring/rider_monitoring_stat_card_test.dart
//
// REGRESSION: sa 1366px desktop ay 6 na card ang isang row (~168px bawat isa).
// Dati, katabi ng icon ang subtitle kaya napuputol ito: "8 installm…",
// "108.8% o…", "0 installm…". Nasa sariling linya na ngayon ang subtitle at
// naka-cap sa 100% ang performance.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/theme/app_colors.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_monitoring/widgets/rider_monitoring_stat_card.dart';

Future<void> _pumpCard(
  WidgetTester tester, {
  required String value,
  required String title,
  String? subtitle,
  double width = 168,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: RiderMonitoringStatCard(
              title: title,
              value: value,
              icon: Icons.folder_outlined,
              color: AppColors.info,
              subtitle: subtitle,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('subtitle ay buo sa 168px na card (walang ellipsis)',
      (tester) async {
    await _pumpCard(
      tester,
      value: '4',
      title: 'Total Assigned Accounts',
      subtitle: '8 installments',
    );

    expect(tester.takeException(), isNull);
    expect(find.text('8 installments'), findsOneWidget);

    final subtitle = tester.renderObject<RenderParagraph>(
      find.text('8 installments'),
    );
    expect(subtitle.didExceedMaxLines, isFalse,
        reason: 'Naputol ang subtitle sa makitid na card');

    // Nasa ibaba ng halaga ang subtitle, hindi katabi ng icon.
    final valueRect = tester.getRect(find.text('4'));
    final subtitleRect = tester.getRect(find.text('8 installments'));
    expect(subtitleRect.top, greaterThan(valueRect.bottom));
  });

  testWidgets('performance subtitle na lampas 100% ay naka-cap',
      (tester) async {
    await _pumpCard(
      tester,
      value: '₱105,922.00',
      title: 'Total Confirmed Collections',
      subtitle: '${riderPerformanceLabel(108.8)} of due',
    );

    expect(find.text('100.0% of due'), findsOneWidget);
    final subtitle = tester.renderObject<RenderParagraph>(
      find.text('100.0% of due'),
    );
    expect(subtitle.didExceedMaxLines, isFalse);
  });

  test('riderPerformanceLabel: cap sa 100%, may 1 decimal', () {
    expect(riderPerformanceLabel(166.7), '100.0%');
    expect(riderPerformanceLabel(100), '100.0%');
    expect(riderPerformanceLabel(99.94), '99.9%');
    expect(riderPerformanceLabel(0), '0.0%');
    expect(riderPerformanceLabel(-5), '0.0%');
    expect(riderPerformanceLabel(null), '—');
  });
}
