// test/features/head_manager/reports/loan_records_preview_test.dart
//
// Ang Interest Report ay may 8 fields kada loan sa API
// (loanNumber, lenderName, principalAmount, interestRate, interestAmount,
// totalPayable, outstandingBalance, status).
//
// Sinusuri dito:
//   * naka-table ang rows tulad ng Loan Records page (Lender & Loan,
//     Amount, Interest, Total, Status),
//   * ang na-e-export ay **Loan Record, Loan Name, Amount, Interest, Total**,
//   * ₱ ang halaga at `N/A` ang walang datos,
//   * tama ang totals sa summary cards (binabalewala ang N/A),
//   * gumagana ang filters (search / Status / Lender) at bumabalik sa page 1,
//   * numbered pagination (1 2 3 4 5 … n) + "Showing x–y of n records",
//   * layout na tulad ng mockup: filter card, apat na stat cards, at
//     "Loan Records" table card na may footer,
//   * ang ine-export na rows ay tatlong column lang at naka-filter.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/features/head_manager/reports/widgets/loan_records_preview.dart';
import 'package:jireta_loans/presentation/shared/widgets/filter_dropdown.dart';
import 'package:jireta_loans/presentation/shared/utils/report_exporter.dart';

/// Rows na kapareho ng ibinabalik ng `reports-generate` para sa
/// `interest_report` template. Kakaibang lender/status kada row para may
/// ma-fi-filter ang tests.
List<Map<String, dynamic>> apiRows(int count) => [
      for (var i = 1; i <= count; i++)
        {
          'loanNumber': 'LN-2025-000$i',
          'lenderName': i.isEven ? 'Maria Santos' : 'Juan Dela Cruz',
          'principalAmount': 10000,
          'interestRate': 20,
          'interestAmount': 2000,
          'totalPayable': 12000,
          'outstandingBalance': 6000,
          'status': i % 3 == 0 ? 'completed' : 'active',
        },
    ];

Future<void> pumpPreview(
  WidgetTester tester,
  List<Map<String, dynamic>> rows, {
  double width = 900,
  DateTimeRange? dateRange,
  VoidCallback? onPickDateRange,
  Widget? exportActions,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: LoanRecordsPreview(
        rows: rows,
        dateRange: dateRange,
        onPickDateRange: onPickDateRange,
        exportActions: exportActions,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('interestPreviewRows', () {
    test('limang column lang ang sinasalin mula sa API rows', () {
      final out = interestPreviewRows(apiRows(1));
      expect(out, hasLength(1));
      expect(out.first.keys.toList(),
          ['Loan Record', 'Loan Name', 'Amount', 'Interest', 'Total']);
      expect(out.first['Loan Record'], 'LN-2025-0001');
      expect(out.first['Loan Name'], 'Juan Dela Cruz');
      expect(out.first['Amount'], 10000);
      expect(out.first['Interest'], 2000);
      expect(out.first['Total'], 12000);
    });

    test('ang export (xlsx) ay limang column lang ang header', () {
      final bytes = buildXlsx(interestPreviewRows(apiRows(2)));
      final archive = ZipDecoder().decodeBytes(bytes);
      final sheet = archive.findFile('xl/worksheets/sheet1.xml');
      expect(sheet, isNotNull);
      final xml = utf8.decode(sheet!.content);

      for (final h in [
        'Loan Record',
        'Loan Name',
        'Amount',
        'Interest',
        'Total'
      ]) {
        expect(xml.contains('<t>$h</t>'), isTrue, reason: 'header $h');
      }
      // Wala na ang ibang field ng Interest Report sa na-export na file.
      expect(xml.contains('interestRate'), isFalse);
      expect(xml.contains('interest_rate'), isFalse);
      expect(xml.contains('outstandingBalance'), isFalse);
      expect(xml.contains('loanNumber'), isFalse);
      expect(xml.contains('lenderName'), isFalse);
    });
  });

  group('LoanRecordsPreview', () {
    testWidgets('naka-table ang rows tulad ng Loan Records page',
        (tester) async {
      await pumpPreview(tester, apiRows(3));

      for (final h in [
        'LENDER & LOAN',
        'AMOUNT',
        'INTEREST',
        'TOTAL',
        'STATUS'
      ]) {
        expect(find.text(h), findsOneWidget, reason: 'header $h');
      }
      // Loan number (bold) + pangalan ng lender sa isang column.
      expect(find.text('LN-2025-0001'), findsOneWidget);
      expect(find.text('Juan Dela Cruz'), findsNWidgets(2));
      expect(find.text('Maria Santos'), findsOneWidget);
      expect(find.text('₱10,000.00'), findsNWidgets(3));
      expect(find.text('₱2,000.00'), findsNWidgets(3));
      expect(find.text('₱12,000.00'), findsNWidgets(3));
      // Status: dot + label (Completed kada 3rd row, Active ang iba).
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Active'), findsNWidgets(2));
    });

    testWidgets('walang Status column kapag walang status ang rows',
        (tester) async {
      final rows = [
        for (final r in apiRows(3))
          {...r}..remove('status'),
      ];
      await pumpPreview(tester, rows);

      expect(find.text('STATUS'), findsNothing);
      expect(find.text('LENDER & LOAN'), findsOneWidget);
      expect(find.text('TOTAL'), findsOneWidget);
    });

    testWidgets('totals ng summary cards ay tama at hindi kasama ang N/A',
        (tester) async {
      await pumpPreview(tester, [
        ...apiRows(2),
        {
          'loanNumber': 'LN-2025-0003',
          'lenderName': 'Pedro Reyes',
          'principalAmount': 5000,
          'interestAmount': null, // walang interest data pa
          'totalPayable': 6000,
          'status': 'active',
        },
      ]);

      expect(find.text('Loans'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Total Amount'), findsOneWidget);
      expect(find.text('₱25,000.00'), findsOneWidget); // 10k + 10k + 5k
      expect(find.text('Total Interest'), findsOneWidget);
      expect(find.text('₱4,000.00'), findsOneWidget); // 2k + 2k (N/A ignored)
      expect(find.text('Total Payable'), findsOneWidget);
      expect(find.text('₱30,000.00'), findsOneWidget); // 12k + 12k + 6k
      // Ang N/A ay ipinapakita pa rin sa cell.
      expect(find.text('N/A'), findsOneWidget);
    });

    testWidgets('numbered pagination (1 2 3 4 5 … n) at paging',
        (tester) async {
      await pumpPreview(tester, apiRows(124));

      expect(find.text('Showing 1–10 of 124 records'), findsOneWidget);
      for (final p in ['1', '2', '3', '4', '5', '13']) {
        expect(find.text(p), findsOneWidget, reason: 'page $p button');
      }
      expect(find.text('…'), findsOneWidget);
      expect(find.text('Loan Records'), findsOneWidget);
      // Filter card: may label ang mga dropdown.
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Lender'), findsOneWidget);

      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();

      expect(find.text('Showing 11–20 of 124 records'), findsOneWidget);
      expect(find.text('₱10,000.00'), findsNWidgets(10));
    });

    testWidgets('footer ("Showing …" + arrows) ay nasa KANAN',
        (tester) async {
      await pumpPreview(tester, apiRows(124), width: 1200);

      final showing = tester.getRect(find.text('Showing 1–10 of 124 records'));
      final nextBtn = tester.getCenter(find.byIcon(Icons.chevron_right_rounded).last);
      // Sa widget test, bawat glyph ay isang em box — kaya mas mahaba ang
      // label kaysa sa totoong app. Sapat na ang relative na pagsusuri.

      // Pati "Showing x–y of n records" ay naka-right, hindi naka-pin sa kaliwa.
      expect(showing.left, greaterThan(400),
          reason: 'dapat nasa kanang bahagi din ang label (hindi naka-pin sa kaliwa)');
      // Nasa dulong kanan pa rin ang mga page button.
      expect(nextBtn.dx, greaterThan(1000),
          reason: 'dapat nasa kanan ang pagination');
      expect(nextBtn.dx - showing.right, lessThan(400),
          reason: 'magkasama sa kanan ang label at pager');
    });

    testWidgets('search filter ay nagfi-filter sa table at totals',
        (tester) async {
      await pumpPreview(tester, apiRows(10));

      expect(find.text('Showing 1–10 of 10 records'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Maria');
      await tester.pumpAndSettle();

      // 5 sa 10 ang Maria Santos.
      expect(find.text('₱50,000.00'), findsOneWidget); // Total Amount
      expect(find.text('5'), findsOneWidget); // Loans card
      // Naka-reset na sa page 1 ang pagination.
      expect(find.text('Showing 1–5 of 5 records'), findsOneWidget);
    });

    testWidgets('Status dropdown ay nagfi-filter at bumabalik sa page 1',
        (tester) async {
      await pumpPreview(tester, apiRows(30));

      // Pumunta muna sa page 2 bago mag-filter.
      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();
      expect(find.text('Showing 11–20 of 30 records'), findsOneWidget);

      await tester.tap(find.text('All Status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('completed').last);
      await tester.pumpAndSettle();

      // Kada 3rd row ang completed → 10 sa 30.
      expect(find.text('Showing 1–10 of 10 records'), findsOneWidget);
      expect(find.text('₱100,000.00'), findsOneWidget); // Total Amount
    });

    testWidgets('Lender dropdown ay nagfi-filter', (tester) async {
      await pumpPreview(tester, apiRows(6));

      await tester.tap(find.text('All Lenders'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maria Santos').last);
      await tester.pumpAndSettle();

      // Even rows lang ang kay Maria Santos → 3 sa 6.
      expect(find.text('Showing 1–3 of 3 records'), findsOneWidget);
      expect(find.text('₱3,000.00'), findsNothing); // walang maling total
      expect(find.text('₱30,000.00'), findsOneWidget); // Total Amount
    });

    testWidgets('date pill at Export button ay lumalabas kapag may props',
        (tester) async {
      var picked = false;
      await pumpPreview(
        tester,
        apiRows(3),
        dateRange: DateTimeRange(
            start: DateTime(2025, 9, 1), end: DateTime(2025, 9, 30)),
        onPickDateRange: () => picked = true,
        exportActions: const Text('EXPORT'),
      );

      expect(find.text('Sep 01, 2025 – Sep 30, 2025'), findsOneWidget);
      expect(find.text('EXPORT'), findsOneWidget);

      await tester.tap(find.text('Sep 01, 2025 – Sep 30, 2025'));
      await tester.pumpAndSettle();
      expect(picked, isTrue);
    });

    testWidgets('walang date pill/Export sa preview modal (walang props)',
        (tester) async {
      await pumpPreview(tester, apiRows(3));
      expect(find.textContaining('– 2025'), findsNothing);
      expect(find.text('EXPORT'), findsNothing);
    });

    testWidgets('walang tugmang row → empty state, hindi blangkong table',
        (tester) async {
      await pumpPreview(tester, apiRows(3));

      await tester.enterText(find.byType(TextField), 'wala ito');
      await tester.pumpAndSettle();

      expect(find.text('No loans match the current filters.'), findsOneWidget);
      expect(find.text('Showing 1–0 of 0 records'), findsNothing);
    });

    testWidgets('walang loan sa period → ibang mensahe kaysa sa filter',
        (tester) async {
      await pumpPreview(tester, const []);

      expect(find.text('No loans in the selected period.'), findsOneWidget);
      expect(find.text('No loans match the current filters.'), findsNothing);
    });

    testWidgets('kapag may leadingFilters (Report Type), hindi Status ang una',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LoanRecordsPreview(
            rows: apiRows(3),
            leadingFilters: [
              labeledFilterField(
                'Report Type',
                FilterDropdown<String>(
                  value: 'loan_records',
                  items: const [
                    DropdownMenuItem(
                        value: 'loan_records', child: Text('Loan Records')),
                  ],
                  onChanged: (_) {},
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Report Type'), findsOneWidget);
      // Isa sa table title ('Loan Records') at isa sa dropdown value.
      expect(find.text('Loan Records'), findsNWidgets(2));
      expect(find.text('Status'), findsNothing);
      expect(find.text('Lender'), findsOneWidget);
    });

    testWidgets('ang ine-export ay ang naka-filter na loan records',
        (tester) async {
      List<Map<String, dynamic>>? exported;
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LoanRecordsPreview(
            rows: apiRows(6),
            onFilteredChanged: (rows) => exported = rows,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Simula pa lang: buong set na tatlong column lang.
      expect(exported, hasLength(6));
      expect(exported!.first.keys.toList(),
          ['Loan Record', 'Loan Name', 'Amount', 'Interest', 'Total']);

      await tester.enterText(find.byType(TextField), 'Maria');
      await tester.pumpAndSettle();

      // Pagkatapos ng filter: 3 rows lang (even numbers) ang ie-export.
      expect(exported, hasLength(3));
      expect(exported!.every((r) => r['Total'] == 12000), isTrue);
    });
  });
}
