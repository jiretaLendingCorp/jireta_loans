// test/app_date_range_picker_test.dart
//
// LOADING NG APPLY / TODAY BUTTON ng custom date-range modal
// (`showAppDateRangePicker`).
//
// Dati: pag-pindot ng Apply, agad na nagsasara ang modal at agad na lumalabas
// ang (lumang) loan records — walang loading. Ngayon: kapag may `onApply`,
// nananatiling bukas ang modal at naka-spinner ang pinindot na button hanggang
// matapos ang load; saka lang ito isinasara.
//
// Sinusuri dito:
//   * Apply: naka-spinner habang tumatakbo ang onApply, bukas pa ang modal,
//   * Today: pareho ring naka-spinner,
//   * sarado na ang modal + naibalik ang range pagkatapos ng load,
//   * walang onApply → agad na nagsasara pa rin (dating behavior).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/core/utils/timezone.dart';
import 'package:jireta_loans/presentation/shared/widgets/forms/app_date_range_picker.dart';

/// Isang simpleng pindutan na nagbubukas ng picker, para makapag-tap sa Apply /
/// Today ng modal at ma-record ang mga resulta.
Future<void> pumpOpener(
  WidgetTester tester, {
  required Future<void> Function(DateTimeRange range) onApply,
  required void Function(DateTimeRange? range) onResult,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final range = await showAppDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                initialDateRange: DateTimeRange(
                    start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 10)),
                showToday: true,
                onApply: onApply,
              );
              onResult(range);
            },
            child: const Text('buksan'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('buksan'));
  await tester.pumpAndSettle();
}

void main() {
  group('Apply button: naglo-loading habang tumatakbo ang onApply', () {
    testWidgets('naka-spinner at bukas pa ang modal hanggang matapos',
        (tester) async {
      final load = Completer<void>();
      DateTimeRange? applied;
      DateTimeRange? returned;

      await pumpOpener(
        tester,
        onApply: (range) {
          applied = range;
          return load.future;
        },
        onResult: (range) => returned = range,
      );

      expect(find.text('Select Date Range'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await tester.pump();

      // Naglo-load na: spinner ang nasa button at hindi pa isinasara ang modal.
      expect(applied, isNotNull, reason: 'naipadala agad ang range sa onApply');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Apply'), findsNothing);
      expect(find.text('Select Date Range'), findsOneWidget);
      expect(returned, isNull, reason: 'bukas pa ang modal');

      load.complete();
      await tester.pumpAndSettle();

      // Pagkatapos ng load: sarado na ang modal at naibalik ang range.
      expect(find.text('Select Date Range'), findsNothing);
      expect(returned, isNotNull);
      expect(returned!.start, DateTime(2026, 10, 1));
      expect(returned!.end, DateTime(2026, 10, 10));
    });

    testWidgets('nabigo ang onApply → hindi naipit ang user sa modal',
        (tester) async {
      DateTimeRange? returned;

      await pumpOpener(
        tester,
        onApply: (_) async => throw StateError('load failed'),
        onResult: (range) => returned = range,
      );

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('Select Date Range'), findsNothing);
      expect(returned, isNotNull);
    });
  });

  group('Today button: naglo-loading din habang tumatakbo ang onApply', () {
    testWidgets('naka-spinner ang Today at bukas pa ang modal', (tester) async {
      final load = Completer<void>();
      DateTimeRange? applied;

      await pumpOpener(
        tester,
        onApply: (range) {
          applied = range;
          return load.future;
        },
        onResult: (_) {},
      );

      await tester.tap(find.text('Today'));
      await tester.pump();

      final now = nowManila();
      final today = DateTime(now.year, now.month, now.day);
      expect(applied, isNotNull);
      expect(applied!.start, today);
      expect(applied!.end, today);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Select Date Range'), findsOneWidget);

      load.complete();
      await tester.pumpAndSettle();

      expect(find.text('Select Date Range'), findsNothing);
    });
  });

  group('Walang onApply → dating behavior (agad na nagsasara)', () {
    testWidgets('Apply ay walang spinner at agad na isinasara', (tester) async {
      DateTimeRange? returned;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  returned = await showAppDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                    initialDateRange: DateTimeRange(
                        start: DateTime(2026, 10, 1),
                        end: DateTime(2026, 10, 10)),
                  );
                },
                child: const Text('buksan'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('buksan'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Select Date Range'), findsNothing);
      expect(returned, isNotNull);
    });
  });
}
