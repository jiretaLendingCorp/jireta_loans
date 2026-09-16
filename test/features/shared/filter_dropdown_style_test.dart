// test/features/shared/filter_dropdown_style_test.dart
//
// Ang lahat ng filter controls sa isang list toolbar (`Filter Date`, results
// chip, at ang mga dropdown) ay DAPAT magkapareho ng ayos: 48px ang taas,
// 8px radius, manipis na border, at walang underline.
//
// Dati: ang `All Roles` / `All Status` ay hilaw na `DropdownButton` (may
// underline, ibang taas) sa tabi ng bordered pills — kaya hindi pantay ang
// dating ng toolbar (hal. `/hm/all-users`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/shared/widgets/filter_dropdown.dart';
import 'package:jireta_loans/presentation/shared/widgets/search_date_filter.dart';
import 'package:jireta_loans/presentation/shared/widgets/search_results_chip.dart';

void main() {
  Future<void> pumpToolbar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const SearchDateFilter(value: null, onChanged: _noopRange),
                const SizedBox(width: 12),
                const SearchResultsChip(count: 20),
                const SizedBox(width: 12),
                FilterDropdown<String>(
                  value: 'all',
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Roles')),
                    DropdownMenuItem(value: 'lender', child: Text('Lender')),
                  ],
                  onChanged: (_) {},
                ),
                const SizedBox(width: 12),
                FilterDropdown<String>(
                  value: 'all',
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Status')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                  ],
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Apat na filter pills: Filter Date, results chip, at dalawang dropdown.
  List<Finder> fourPills() => [
        find.byType(SearchDateFilter),
        find.byType(SearchResultsChip),
        find.byType(FilterDropdown<String>).at(0),
        find.byType(FilterDropdown<String>).at(1),
      ];

  testWidgets('pareho ang laki at linya ng apat na filter pills', (tester) async {
    await pumpToolbar(tester);
    expect(tester.takeException(), isNull);

    final pills = fourPills();
    final dys = <double>[];
    for (final pill in pills) {
      expect(tester.getSize(pill).height, 48,
          reason: 'Hindi 48px ang taas ng pill');
      dys.add(tester.getCenter(pill).dy);
    }
    // Magkapantay: pareho ang vertical center ng lahat ng pills.
    for (final dy in dys) {
      expect(dy, closeTo(dys.first, 0.5));
    }
  });

  testWidgets('may border at 8px radius ang dropdown pill, walang underline',
      (tester) async {
    await pumpToolbar(tester);

    final dropdowns = find.byType(FilterDropdown<String>);
    expect(dropdowns, findsNWidgets(2));

    for (final pill in [dropdowns.at(0), dropdowns.at(1)]) {
      final decoration = tester
          .widget<Container>(
              find.descendant(of: pill, matching: find.byType(Container)).first)
          .decoration as BoxDecoration;
      expect(decoration.border, isNotNull,
          reason: 'Walang border ang dropdown pill');
      expect(decoration.borderRadius, BorderRadius.circular(8));
      expect(
        find.descendant(
            of: pill, matching: find.byType(DropdownButtonHideUnderline)),
        findsOneWidget,
        reason: 'May underline pa ang dropdown',
      );
    }
  });
}

void _noopRange(DateTimeRange? _) {}
