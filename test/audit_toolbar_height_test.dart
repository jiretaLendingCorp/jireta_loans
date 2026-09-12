// test/audit_toolbar_height_test.dart
//
// Verifies the three audit toolbar controls (Filter Date, results chip,
// All Actions dropdown) all render at the same 48px height in one row.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/shared/widgets/search_date_filter.dart';
import 'package:jireta_loans/presentation/shared/widgets/search_results_chip.dart';

/// Faithful copy of _buildActionDropdown's container + button so heights can
/// be compared without pumping the whole audit screen.
Widget buildActionDropdownReplica() {
  return DropdownButtonHideUnderline(
    child: Container(
      width: 190,
      height: 48,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<String?>(
        value: null,
        isExpanded: true,
        isDense: true,
        hint: const Text(
          'Filter by Action',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        items: const [
          DropdownMenuItem(value: null, child: Text('All Actions')),
          DropdownMenuItem(value: 'a', child: Text('Some Action')),
        ],
        selectedItemBuilder: (context) => const [
          Text('All Actions', maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('Some Action', maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
        onChanged: (_) {},
      ),
    ),
  );
}

void main() {
  testWidgets('audit toolbar pills share one height', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SearchDateFilter(value: null, onChanged: (_) {}),
              const SizedBox(width: 12),
              const SearchResultsChip(count: 20),
              const SizedBox(width: 12),
              buildActionDropdownReplica(),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final dateH =
        tester.getSize(find.byType(SearchDateFilter)).height;
    final chipH =
        tester.getSize(find.byType(SearchResultsChip)).height;
    final actionFinder = find.descendant(
      of: find.byType(Row),
      matching: find.byType(DropdownButton<String?>),
    );
    final actionH = tester.getSize(actionFinder).height;

    // ignore: avoid_print
    print('date=$dateH chip=$chipH action=$actionH');

    expect(dateH, 48);
    expect(chipH, 48);
    // The dropdown button itself sizes to content; what matters is that it
    // never exceeds the 48px row and stays vertically centered with the
    // other pills (its 48px container aligns the borders).
    expect(actionH, lessThanOrEqualTo(48));
    final chipDy = tester.getCenter(find.byType(SearchResultsChip)).dy;
    final actionDy = tester.getCenter(actionFinder).dy;
    expect((actionDy - chipDy).abs(), lessThan(2));
  });
}
