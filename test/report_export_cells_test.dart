// test/report_export_cells_test.dart
// Regression test para sa blangkong cell sa PDF/Excel reports.
//
// (1) `null` / `''` → dati blangko ang cell; ngayon `N/A`.
// (2) Ang lumang em-dash fallback (`—`, U+2014) ay hindi kayang i-render ng
//     built-in na Helvetica ng `pdf` (Latin-1 lang) kaya blangko itong
//     lumalabas sa preview/PDF — `N/A` na rin ito, kaya kahit ang mga lumang
//     report na naka-save sa `reports.data` ay maayos ang labas.
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
