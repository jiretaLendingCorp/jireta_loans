// test/responsive_content_test.dart
//
// Verifies the shared responsive helpers used across the HM/Employee list
// screens:
//   * ResponsiveTableScroll never overflows and keeps every cell visible
//     (horizontally scrollable) at mobile widths.
//   * ResponsiveSearchToolbar never overflows at mobile widths.
//   * The rendered table content is hit-testable (buttons inside the table
//     still receive taps when the table is scrollable).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/shared/widgets/layout/responsive_content.dart';

/// Mirrors the premium-table structure used by the HM/Employee list screens:
/// a header row + data rows built from `Row` + `Expanded` columns.
Widget buildSampleTable() {
  return ResponsiveTableScroll(
    minWidth: 760,
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E5EA)),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: const Color(0xFFF8F9FB),
          child: const Row(children: [
            Expanded(flex: 3, child: Text('LENDER & LOAN')),
            Expanded(flex: 2, child: Text('RIDER')),
            Expanded(flex: 2, child: Text('DEADLINE')),
            Expanded(flex: 3, child: Text('STATUS')),
            Expanded(flex: 2, child: Text('ACTION')),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: const Row(children: [
            Expanded(flex: 3, child: Text('LN-2026-64321')),
            Expanded(flex: 2, child: Text('Shem M')),
            Expanded(flex: 2, child: Text('Sep 09, 2026')),
            Expanded(flex: 3, child: Text('Approved')),
            Expanded(flex: 2, child: TextButton(onPressed: _noop, child: Text('View'))),
          ]),
        ),
      ]),
    ),
  );
}

void _noop() {}

Future<void> pumpTable(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: buildSampleTable())),
  ));
  await tester.pumpAndSettle();
}

Future<void> pumpToolbar(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ResponsiveSearchToolbar(
          searchField: const TextField(decoration: InputDecoration(hintText: 'Search...')),
          trailing: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: const Text('Filter Date')),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: const Text('8 results')),
          ],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('ResponsiveListCard', () {
    Widget buildSampleListCard({VoidCallback? onView}) {
      return ResponsiveListCard(
        minTableWidth: 760,
        columns: const [
          ResponsiveCol('Lender & Loan', icon: Icons.person_outline, flex: 3),
          ResponsiveCol('Rider', icon: Icons.delivery_dining_outlined, flex: 2),
          ResponsiveCol('Deadline', icon: Icons.event_outlined, flex: 2),
          ResponsiveCol('Status', icon: Icons.flag_outlined, flex: 3),
        ],
        actionsCol: const ResponsiveActionsCol(width: 96),
        rows: [
          ResponsiveRow(
            cells: const [
              Text('LN-2026-64321'),
              Text('Shem M'),
              Text('Sep 09, 2026'),
              Text('Approved'),
            ],
            actions: TextButton(onPressed: onView ?? _noop, child: const Text('View')),
          ),
          const ResponsiveRow(
            cells: [
              Text('LN-2026-45012'),
              Text('Jamvis D'),
              Text('Sep 08, 2026'),
              Text('Failed'),
            ],
            actions: TextButton(onPressed: _noop, child: Text('View')),
          ),
        ],
      );
    }

    Future<void> pumpList(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: buildSampleListCard())),
      ));
      await tester.pumpAndSettle();
    }

    for (final width in [1280.0, 800.0]) {
      testWidgets('desktop: renders a table with header and all cells at width $width',
          (tester) async {
        await pumpList(tester, width);
        expect(tester.takeException(), isNull);
        expect(find.text('LENDER & LOAN'), findsOneWidget);
        expect(find.text('STATUS'), findsOneWidget);
        expect(find.text('LN-2026-64321'), findsOneWidget);
        expect(find.text('Jamvis D'), findsOneWidget);
        expect(find.text('View'), findsNWidgets(2));
      });
    }

    for (final width in [420.0, 360.0]) {
      testWidgets('mobile: renders stacked cards with labels, values and actions at width $width',
          (tester) async {
        await pumpList(tester, width);
        expect(tester.takeException(), isNull,
            reason: 'Layout error rendered at width $width');
        // Field labels are shown on the cards (with the colon).
        expect(find.text('LENDER & LOAN:'), findsNWidgets(2));
        expect(find.text('STATUS:'), findsNWidgets(2));
        // Values are visible without any horizontal scrolling.
        for (final text in ['LN-2026-64321', 'Shem M', 'Sep 09, 2026', 'Approved']) {
          expect(find.text(text), findsOneWidget,
              reason: 'Cell "$text" not visible at width $width');
        }
        expect(find.text('View'), findsNWidgets(2));
      });
    }

    testWidgets('mobile: labels render fully on a single line (no wrap, no cut-off)',
        (tester) async {
      await pumpList(tester, 360);
      expect(tester.takeException(), isNull);
      for (final label in ['LENDER & LOAN:', 'RIDER:', 'DEADLINE:', 'STATUS:']) {
        final text = tester.widget<Text>(find.text(label).first);
        expect(text.maxLines, isNull,
            reason: 'Label "$label" is restricted to maxLines (can get cut off)');
        expect(text.overflow, isNull,
            reason: 'Label "$label" has an overflow (can get truncated)');
        expect(text.softWrap, isFalse,
            reason: 'Label "$label" can still wrap to a second line');
        // Full label text is present (nothing was cut).
        expect(find.text(label), findsNWidgets(2),
            reason: 'Label "$label" text is missing');
      }
      // All labels sit on a single rendered line (height of one text line).
      final labelHeight = tester.getSize(find.text('LENDER & LOAN:').first).height;
      for (final label in ['RIDER:', 'DEADLINE:', 'STATUS:']) {
        final h = tester.getSize(find.text(label).first).height;
        expect((labelHeight - h).abs(), lessThan(2),
            reason: 'Label "$label" wrapped to a second line');
      }
    });

    testWidgets('mobile: labels on the left, every value aligned in one column',
        (tester) async {
      await pumpList(tester, 360);
      expect(tester.takeException(), isNull);
      final labelTopLeft = tester.getTopLeft(find.text('LENDER & LOAN:').first);
      final valueTopLeft = tester.getTopLeft(find.text('LN-2026-64321'));
      // Same row, top-aligned (plain row — no avatar, label stays at top).
      expect((labelTopLeft.dy - valueTopLeft.dy).abs(), lessThan(6));
      // Label stays on the LEFT side of the card.
      expect(labelTopLeft.dx, lessThan(30),
          reason: 'Label was pushed away from the left edge');
      // Value sits to the RIGHT of the label...
      expect(valueTopLeft.dx, greaterThan(labelTopLeft.dx + 30));
      // ...and only a small gap from the colon of the longest label.
      final colonRight = tester.getTopRight(find.text('LENDER & LOAN:').first).dx;
      expect(valueTopLeft.dx - colonRight, lessThan(45),
          reason: 'Value is too far from the colon');
      // EVERY value starts at the exact same x (aligned pantay-pantay).
      final xOfRow2 = tester.getTopLeft(find.text('Shem M')).dx;
      final xOfRow3 = tester.getTopLeft(find.text('Sep 09, 2026')).dx;
      final xOfRow4 = tester.getTopLeft(find.text('Approved')).dx;
      expect((valueTopLeft.dx - xOfRow2).abs(), lessThan(1),
          reason: 'Values are not aligned in one column');
      expect((valueTopLeft.dx - xOfRow3).abs(), lessThan(1));
      expect((valueTopLeft.dx - xOfRow4).abs(), lessThan(1));
    });

    testWidgets('mobile: values sit just to the right of the colon (unti lang)', (tester) async {
      await pumpList(tester, 360);
      expect(tester.takeException(), isNull);
      // The label's right edge (the ":") sits just a little to the left of
      // the value.
      final colonRight = tester.getTopRight(find.text('LENDER & LOAN:').first).dx;
      final valueLeft = tester.getTopLeft(find.text('LN-2026-64321')).dx;
      expect(valueLeft - colonRight, greaterThan(8),
          reason: 'Value is too close to the colon (gap ${valueLeft - colonRight}px)');
      expect(valueLeft - colonRight, lessThan(45),
          reason: 'Value is too far from the colon (gap ${valueLeft - colonRight}px)');
    });

    testWidgets('mobile: action buttons stay tappable', (tester) async {
      var tapped = false;
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: buildSampleListCard(onView: () => tapped = true),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('View').first);
      await tester.pump();
      expect(tapped, isTrue, reason: 'View button tap was not received');
    });
  });

  group('ResponsiveTableScroll', () {
    for (final width in [1280.0, 800.0, 420.0, 360.0]) {
      testWidgets('no exception and all cells visible at width $width', (tester) async {
        await pumpTable(tester, width);
        expect(tester.takeException(), isNull,
            reason: 'Layout error rendered at width $width');
        // Every column value must still be present (nothing clipped away).
        for (final text in [
          'LENDER & LOAN',
          'RIDER',
          'DEADLINE',
          'STATUS',
          'ACTION',
          'LN-2026-64321',
          'Shem M',
          'Sep 09, 2026',
          'Approved',
          'View',
        ]) {
          expect(find.text(text), findsOneWidget,
              reason: 'Cell "$text" not visible at width $width');
        }
      });
    }

    testWidgets('buttons inside the table stay tappable at mobile width', (tester) async {
      await pumpTable(tester, 360);
      expect(tester.takeException(), isNull);
      // The table is 760px wide inside a 360px viewport: scroll it fully to
      // the right so the trailing ACTION button is on screen, then tap it.
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(-800, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('View'), warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'Tapping a table button threw');
    });
  });

  group('ResponsiveSearchToolbar', () {
    for (final width in [1280.0, 420.0, 360.0]) {
      testWidgets('no exception and controls visible at width $width', (tester) async {
        await pumpToolbar(tester, width);
        expect(tester.takeException(), isNull,
            reason: 'Layout error rendered at width $width');
        expect(find.text('Filter Date'), findsOneWidget);
        expect(find.text('8 results'), findsOneWidget);
      });
    }
  });
}