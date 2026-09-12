// test/filter_tab_bar_test.dart
//
// Verifies the shared FilterTabBar dropdown:
//   * tapping the button opens a wide overlay menu BELOW it (the navy button
//     itself stays visible, never covered by the menu),
//   * tapping an option reports it and closes the menu.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/shared/widgets/filter_pill_tab.dart';

const _options = [
  FilterTabDef('all', 'All', Icons.layers_outlined),
  FilterTabDef('pending', 'Pending CI', Icons.hourglass_top_rounded),
  FilterTabDef('rejected', 'Rejected', Icons.cancel_rounded),
];

Future<void> pumpBar(
  WidgetTester tester, {
  String? value,
  ValueChanged<String>? onChanged,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: FilterTabBar(
          dropdownLabel: 'Pipeline',
          dropdownOptions: _options,
          dropdownValue: value,
          onDropdownChanged: onChanged ?? (_) {},
          pills: const [],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('FilterTabBar dropdown menu', () {
    testWidgets('opens below the button without covering it', (tester) async {
      await pumpBar(tester, value: 'all');

      // Button shows the selected option.
      expect(find.text('All'), findsOneWidget);

      // Open the menu.
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      // Menu lists every option, button itself still visible on top.
      expect(find.text('Pending CI'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);

      final buttonDy = tester.getTopLeft(find.text('All').first).dy;
      final menuDy = tester.getTopLeft(find.text('Pending CI')).dy;
      expect(menuDy, greaterThan(buttonDy),
          reason: 'Menu must open below the button, not over it');
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping an option reports it and closes the menu',
        (tester) async {
      String? picked;
      await pumpBar(tester,
          value: 'all', onChanged: (v) => picked = v);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Pending CI'), findsOneWidget);

      await tester.tap(find.text('Pending CI'));
      await tester.pumpAndSettle();

      expect(picked, 'pending');
      expect(find.text('Pending CI'), findsNothing,
          reason: 'Menu should close after picking an option');
      expect(tester.takeException(), isNull);
    });
  });
}
