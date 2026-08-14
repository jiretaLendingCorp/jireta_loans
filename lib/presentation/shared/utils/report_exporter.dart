// lib/presentation/shared/utils/report_exporter.dart
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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

String _cell(String ref, dynamic v) {
  if (v == null) return '<c r="$ref"/>';
  return '<c r="$ref" t="inlineStr"><is><t>${_xmlEscape(v.toString())}</t></is></c>';
}

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
Uint8List buildXlsx(
  List<Map<String, dynamic>> rows, {
  String sheetName = 'Sheet1',
}) {
  final cols = _columnsOf(rows);
  final colLetters = [for (var i = 0; i < cols.length; i++) _colLetter(i)];

  final sheet = StringBuffer(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');

  final headerCells = [
    for (var i = 0; i < cols.length; i++) _cell('${colLetters[i]}1', cols[i])
  ].join();
  sheet.write('<row r="1">$headerCells</row>');

  for (var ri = 0; ri < rows.length; ri++) {
    final rn = ri + 2;
    final cells = [
      for (var i = 0; i < cols.length; i++)
        _cell('${colLetters[i]}$rn', rows[ri][cols[i]])
    ].join();
    sheet.write('<row r="$rn">$cells</row>');
  }
  sheet.write('</sheetData></worksheet>');

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
}) async {
  final cols = columns ?? _columnsOf(rows);
  final data = [
    for (final r in rows)
      [for (final c in cols) r[c]?.toString() ?? ''],
  ];

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
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
        pw.SizedBox(height: 14),
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

String sanitizeFileName(String name) =>
    name.replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '_').trim();