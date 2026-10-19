// lib/presentation/shared/utils/report_exporter.dart
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/timezone.dart';

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _colLetter(int i) {
  var col = '';
  i += 1;
  while (i > 0) {
    final rem = (i - 1) % 26;
    col = String.fromCharCode(65 + rem) + col;
    i = (i - 1) ~/ 26;
  }
  return col;
}

/// Halagang ipapakita sa cell ng report — walang blangkong cell.
///
/// (a) `null` / `''` → `N/A` (dati ay blangko).
/// (b) Ang em-dash (`—`, U+2014) na fallback ay HINDI kayang i-render ng
///     built-in na Helvetica ng PDF (Latin-1 lang ang sakop): tahimik itong
///     tinatanggal kaya blangkong cell ang lumalabas sa preview at sa PDF.
///     Ang mga lumang report na naka-save na sa `reports.data` ay may ganitong
///     halaga pa, kaya dito rin sila na-aayos.
/// (c) Ang en-dash (`–`) na fallback ay `N/A` din.
/// (d) Ang hilaw na timestamp (`2026-09-20T16:29:51.064065+00:00`) ay
///     ginagawang "Sep 20, 2026 04:29 PM" (Manila) — kapareho ng bagong
///     format ng `reports-generate`. Saklaw nito pati ang mga LUMANG report na
///     naka-save na sa `reports.data` bago pa naayos ang server.
String reportCellValue(dynamic v) {
  if (v == null) return 'N/A';
  final s = v.toString().trim();
  if (s.isEmpty || s == '—' || s == '–') return 'N/A';
  return _readableDate(v, s);
}

final _isoTimestamp = RegExp(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}');
final _isoDateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// ISO timestamp/date → Manila display string, o `s` kung hindi petsa.
String _readableDate(dynamic raw, String s) {
  if (_isoTimestamp.hasMatch(s)) {
    final dt = parseManila(raw);
    if (dt != null) return DateFormat('MMM dd, yyyy hh:mm a').format(dt);
  } else if (_isoDateOnly.hasMatch(s)) {
    final dt = DateTime.tryParse(s);
    if (dt != null) return DateFormat('MMM dd, yyyy').format(dt);
  }
  return s;
}

String _cell(String ref, dynamic v) =>
    _textCell(ref, reportCellValue(v));

String _textCell(String ref, String text) =>
    '<c r="$ref" t="inlineStr"><is><t>${_xmlEscape(text)}</t></is></c>';

/// Cell ng XLSX — blangko para sa [ReportBlank], at `₱50,000.00` para sa
/// money columns.
String _cellFor(String ref, dynamic v, {bool money = false}) {
  if (v is ReportBlank) return '<c r="$ref"/>';
  if (money) {
    final n = _exportNum(v);
    if (n != null) return _textCell(ref, _summaryMoney(n, '₱'));
  }
  return _cell(ref, v);
}

/// Sentinel para sa TUNAY na blangkong cell sa exports — hindi ito nagiging
/// `N/A` (tulad ng `null` / `''`) kaya isang TOTAL lang ang nasa kaliwa ng
/// TOTAL row.
class ReportBlank {
  const ReportBlank();
}

const ReportBlank reportBlank = ReportBlank();

/// Mga column na pera — naka-format na may comma, `.00`, at currency prefix.
const Set<String> _moneyColumns = {'Amount', 'Interest', 'Total'};

bool _isMoneyColumn(String label) => _moneyColumns.contains(label);

double? _exportNum(dynamic v) {
  if (v is num) return v.toDouble();
  final s = (v ?? '')
      .toString()
      .replaceAll(RegExp(r'[₱,\s]'), '')
      .replaceAll('PHP', '')
      .trim();
  return num.tryParse(s)?.toDouble();
}

/// Summary ng napiling panahon na nakalagay sa TAAS ng PDF/Excel report —
/// tugma sa format ng Reports page:
///
/// Beginning Date | Ending Date | Amount Collected |
/// Amount to Collect | Income
///
/// Sinusundan ito ng TOTAL row na nagbubuod sa tatlong halaga. Pareho ito sa
/// nakikita sa screen, kaya hindi na kailangang buksan ang app para makita ang
/// kabuuan ng panahon.
class ReportSummary {
  final String beginningDate;
  final String endingDate;
  final double collected;
  final double outstanding;
  final double income;

  const ReportSummary({
    required this.beginningDate,
    required this.endingDate,
    required this.collected,
    required this.outstanding,
    required this.income,
  });

  static const List<String> headers = [
    'Beginning Date',
    'Ending Date',
    'Amount Collected',
    'Amount to Collect',
    'Income',
  ];

  /// Isang row ng halaga. [currency] = `₱` sa Excel; `PHP ` sa PDF dahil ang
  /// built-in na Helvetica ay walang glyph para sa peso sign.
  List<String> values({required String currency}) => [
        beginningDate,
        endingDate,
        _summaryMoney(collected, currency),
        _summaryMoney(outstanding, currency),
        _summaryMoney(income, currency),
      ];

  /// TOTAL row ng summary — nasa Ending Date column ang `TOTAL` (malapit sa
  /// mga halaga), at blangko ang Beginning Date cell.
  List<dynamic> totals({required String currency}) => [
        reportBlank,
        'TOTAL',
        _summaryMoney(collected, currency),
        _summaryMoney(outstanding, currency),
        _summaryMoney(income, currency),
      ];
}

String _summaryMoney(double v, String currency) =>
    '$currency${NumberFormat('#,##0.00', 'en_PH').format(v)}';

List<String> _columnsOf(List<Map<String, dynamic>> rows) {
  final cols = <String>[];
  for (final r in rows) {
    for (final k in r.keys) {
      if (!cols.contains(k)) cols.add(k);
    }
  }
  if (cols.isEmpty) cols.add('No Data');
  return cols;
}

/// Builds a minimal, valid .xlsx workbook from a list of row maps.
///
/// Kapag may [summary], naka-print ito sa TAAS ng table (Beginning Date /
/// Ending Date / Amount Collected / Amount to Collect / Income) na
/// may TOTAL row, saka isang blangkong row bago ang detalyadong table.
Uint8List buildXlsx(
  List<Map<String, dynamic>> rows, {
  String sheetName = 'Sheet1',
  ReportSummary? summary,
}) {
  final cols = _columnsOf(rows);

  final sheet = StringBuffer(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      // A4 print setup: laging A4 (paperSize 9), landscape, at fit sa isang
      // page ang lapad — automatic kapag ini-print mula sa Excel.
      '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
      '<sheetData>');

  var rn = 1;
  void writeRow(List<dynamic> values, {Set<int> moneyIndexes = const {}}) {
    final cells = [
      for (var i = 0; i < values.length; i++)
        _cellFor('${_colLetter(i)}$rn', values[i],
            money: moneyIndexes.contains(i)),
    ].join();
    sheet.write('<row r="$rn">$cells</row>');
    rn++;
  }

  final moneyIndexes = <int>{
    for (var i = 0; i < cols.length; i++)
      if (_isMoneyColumn(cols[i])) i,
  };

  if (summary != null) {
    writeRow(['Loan Summary']);
    writeRow(ReportSummary.headers);
    writeRow(summary.values(currency: '₱'));
    writeRow(summary.totals(currency: '₱'));
    rn++; // blangkong row sa pagitan ng summary at ng detalye
  }

  writeRow(['Loan Records']);
  writeRow(cols);
  for (final r in rows) {
    writeRow([for (final c in cols) r[c]], moneyIndexes: moneyIndexes);
  }
  sheet.write('</sheetData>');
  sheet.write('<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" '
      'header="0.3" footer="0.3"/>');
  sheet.write('<pageSetup paperSize="9" orientation="landscape" '
      'fitToWidth="1" fitToHeight="0"/>');
  sheet.write('</worksheet>');

  final safeSheet = _xmlEscape(sheetName);
  const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>''';

  const rootRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';

  final workbook = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheets><sheet name="$safeSheet" sheetId="1" r:id="rId1"/></sheets>
</workbook>''';

  const workbookRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>''';

  final archive = Archive()
    ..addFile(ArchiveFile.string('[Content_Types].xml', contentTypes))
    ..addFile(ArchiveFile.string('_rels/.rels', rootRels))
    ..addFile(ArchiveFile.string('xl/workbook.xml', workbook))
    ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', workbookRels))
    ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', sheet.toString()));

  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded);
}

/// Builds a landscape PDF table report from a list of row maps.
Future<Uint8List> buildPdf({
  required String title,
  required List<Map<String, dynamic>> rows,
  List<String>? columns,
  ReportSummary? summary,
}) async {
  final cols = columns ?? _columnsOf(rows);
  // Ang Amount / Interest / Total ay naka-`PHP 50,000.00` (comma + .00) —
  // kapareho ng itsura ng Loan Summary sa itaas ng report.
  final data = [
    for (final r in rows)
      [for (final c in cols) _pdfCellText(r[c], c)],
  ];

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      // A4 automatic — landscape para magkasya ang table sa isang page.
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(20),
      header: (ctx) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Jireta Loans & Credit Corp',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
          ),
          pw.Text(
            'Generated ${DateTime.now().toString().substring(0, 16)}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
          ),
        ],
      ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${ctx.pageNumber}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
        ),
      ),
      build: (ctx) => [
        pw.Text(
          title,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
              fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        if (summary != null) ...[
          pw.SizedBox(height: 12),
          pw.Text('Loan Summary',
              style:
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ReportSummary.headers,
            data: <List<dynamic>>[
              summary.values(currency: 'PHP '),
              [
                for (final v in summary.totals(currency: 'PHP '))
                  v is ReportBlank ? '' : v,
              ],
            ],
            border: const pw.TableBorder(
              top: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
              bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
              left: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
              right: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
              horizontalInside:
                  pw.BorderSide(color: PdfColors.grey400, width: 0.4),
              verticalInside:
                  pw.BorderSide(color: PdfColors.grey400, width: 0.4),
            ),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.all(4),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
        pw.SizedBox(height: 14),
        pw.Text('Loan Records',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        if (rows.isEmpty)
          pw.Text(
            'No data available.',
            style: const pw.TextStyle(color: PdfColors.grey600),
          )
        else
          pw.TableHelper.fromTextArray(
            headers: cols,
            data: data,
            border: const pw.TableBorder(
              top: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
              bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
              left: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
              right: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
              horizontalInside:
                  pw.BorderSide(color: PdfColors.grey400, width: 0.4),
              verticalInside:
                  pw.BorderSide(color: PdfColors.grey400, width: 0.4),
            ),
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey800),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.all(4),
            cellAlignment: pw.Alignment.centerLeft,
          ),
      ],
    ),
  );
  return doc.save();
}

/// Text ng isang cell sa PDF — blangko para sa [ReportBlank], at
/// `PHP 50,000.00` para sa money columns.
String _pdfCellText(dynamic v, String column) {
  if (v is ReportBlank) return '';
  if (_isMoneyColumn(column)) {
    final n = _exportNum(v);
    if (n != null) return _summaryMoney(n, 'PHP ');
  }
  return reportCellValue(v);
}

String sanitizeFileName(String name) =>
    name.replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '_').trim();