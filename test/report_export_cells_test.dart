// test/report_export_cells_test.dart
// Regression test para sa blangkong cell sa PDF/Excel reports.
//
// (1) `null` / `''` → dati blangko ang cell; ngayon `N/A`.
// (2) Ang lumang em-dash fallback (`—`, U+2014) ay hindi kayang i-render ng
//     built-in na Helvetica ng `pdf` (Latin-1 lang) kaya blangko itong
//     lumalabas sa preview/PDF — `N/A` na rin ito, kaya kahit ang mga lumang
//     report na naka-save sa `reports.data` ay maayos ang labas.
// (3) Ang summary ng panahon (Beginning Date, Ending Date, nakolekta, hindi pa
//     nakokolekta, income) at TOTAL row ay kasama na sa PDF/Excel.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/shared/utils/report_exporter.dart';

void main() {
  group('reportCellValue', () {
    test('null at blangkong string ay N/A, hindi blangko', () {
      expect(reportCellValue(null), 'N/A');
      expect(reportCellValue(''), 'N/A');
      expect(reportCellValue('   '), 'N/A');
    });

    test('em-dash at en-dash fallback ay N/A', () {
      expect(reportCellValue('—'), 'N/A');
      expect(reportCellValue('–'), 'N/A');
    });

    test('totoong halaga ay hindi ginalaw (kasama ang zero at false)', () {
      expect(reportCellValue('Liza De Guzman'), 'Liza De Guzman');
      expect(reportCellValue(0), '0');
      expect(reportCellValue(false), 'false');
      expect(reportCellValue(1500.5), '1500.5');
    });

    test('hilaw na Manila-as-UTC timestamp ay ginagawang mababasang petsa', () {
      expect(
        reportCellValue('2026-09-20T16:29:51.064065+00:00'),
        'Sep 21, 2026 12:29 AM',
      );
    });

    test('date-only (due date) ay walang oras', () {
      expect(reportCellValue('2026-09-20'), 'Sep 20, 2026');
    });
  });

  group('buildXlsx', () {
    test('walang blangkong cell — N/A ang walang laman', () {
      final bytes = buildXlsx([
        {'lenderName': 'Liza De Guzman', 'phoneNumber': '09465227135'},
        {'lenderName': null, 'phoneNumber': '—'},
      ]);

      // Ang .xlsx ay ZIP — buksan ang worksheet bago i-assert.
      final archive = ZipDecoder().decodeBytes(bytes);
      final sheet = archive.findFile('xl/worksheets/sheet1.xml');
      expect(sheet, isNotNull);
      final xml = utf8.decode(sheet!.content);

      expect(xml.contains('<t>N/A</t>'), isTrue);
      // Walang cell na inlineStr na walang laman na teksto.
      expect(xml.contains('<is><t></t></is>'), isFalse);
      expect(xml.contains('Liza De Guzman'), isTrue);
    });
  });

  group('ReportSummary sa exports', () {
    const summary = ReportSummary(
      beginningDate: 'Sep 01, 2026',
      endingDate: 'Sep 30, 2026',
      collected: 12000,
      outstanding: 5000,
      income: 3000,
    );

    test('xlsx: summary (Beginning/Ending Date, amount, TOTAL) bago ang table',
        () {
      final bytes = buildXlsx(
        [
          {'Loan Record': 'LN-1', 'Amount': 10000},
        ],
        summary: summary,
      );
      final xml = utf8.decode(
          ZipDecoder().decodeBytes(bytes).findFile('xl/worksheets/sheet1.xml')!.content);

      for (final h in ReportSummary.headers) {
        expect(xml.contains('<t>$h</t>'), isTrue, reason: 'summary header $h');
      }
      expect(xml.contains('<t>Sep 01, 2026</t>'), isTrue);
      expect(xml.contains('<t>Sep 30, 2026</t>'), isTrue);
      expect(xml.contains('<t>₱12,000.00</t>'), isTrue); // nakolekta
      expect(xml.contains('<t>₱5,000.00</t>'), isTrue); // hindi pa
      expect(xml.contains('<t>₱3,000.00</t>'), isTrue); // kita
      expect(xml.contains('<t>TOTAL</t>'), isTrue);

      // May hiwalay na Loan Summary at Loan Records section, at nasa itaas ng
      // detalye ang summary.
      expect(xml.contains('<t>Loan Summary</t>'), isTrue);
      expect(xml.contains('<t>Loan Records</t>'), isTrue);
      expect(xml.indexOf('<t>Loan Summary</t>'),
          lessThan(xml.indexOf('<t>Loan Records</t>')));

      // A4 print setup — automatic kapag ini-print mula sa Excel.
      expect(xml.contains('paperSize="9"'), isTrue);
      expect(xml.contains('fitToPage="1"'), isTrue);

      // Ang Amount ay `₱10,000.00` (comma at .00), kapareho ng summary.
      expect(xml.contains('<t>₱10,000.00</t>'), isTrue);
      expect(xml.contains('<t>10000</t>'), isFalse);
    });

    test('isang TOTAL lang sa kaliwa at blangko ang susunod na cell', () {
      final bytes = buildXlsx(
        [
          {
            'Loan Record': 'LN-1',
            'Loan Name': 'Juan Dela Cruz',
            'Amount': 50000,
            'Interest': 10000,
            'Total': 60000,
          },
          {
            'Loan Record': reportBlank,
            'Loan Name': 'TOTAL',
            'Amount': 50000,
            'Interest': 10000,
            'Total': 60000,
          },
        ],
        summary: summary,
      );
      final xml = utf8.decode(
          ZipDecoder().decodeBytes(bytes).findFile('xl/worksheets/sheet1.xml')!.content);

      // Isa sa Loan Summary TOTAL row, isa sa Loan Records TOTAL row.
      expect(RegExp('<t>TOTAL</t>').allMatches(xml).length, 2);
      // Hindi naging `N/A` ang blangkong pangalawang cell.
      expect(xml.contains('<t>N/A</t>'), isFalse);
      // Naka-format ang mga halaga ng Loan Records.
      expect(xml.contains('<t>₱50,000.00</t>'), isTrue);
      expect(xml.contains('<t>₱10,000.00</t>'), isTrue);
      expect(xml.contains('<t>₱60,000.00</t>'), isTrue);
    });

    test('pdf: kasama ang summary at hindi nag-e-error', () async {
      final bytes = await buildPdf(
        title: 'Interest Report',
        rows: [
          {'Loan Record': 'LN-1', 'Total': 12000},
        ],
        summary: summary,
      );
      expect(bytes.isNotEmpty, isTrue);
    });
  });

  test('buildPdf ay may laman at hindi nag-e-error sa blangkong row', () async {
    final bytes = await buildPdf(
      title: 'Account Upgrade Report',
      rows: [
        {'lenderName': 'Liza De Guzman', 'verificationStatus': 'verified'},
        {'lenderName': null, 'verificationStatus': '—'},
      ],
    );
    expect(bytes.isNotEmpty, isTrue);
  });
}
