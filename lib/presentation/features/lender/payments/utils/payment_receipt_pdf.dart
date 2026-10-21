// lib/presentation/features/lender/payments/utils/payment_receipt_pdf.dart
//
// PDF ng lender payment receipt — ito ang isinasave ng "Download Receipt"
// kapag walang hosted receipt. Dating wala talagang downloadable artifact ang
// screen:
// "Download"/"Share" lang at naka-depende sa `receipt_url`, kaya kapag `null`
// (madalas sa GCash/Xendit payments) ay WALANG button na lumalabas at walang
// paraan para i-print ang resibo.
//
// ASCII lang ang nilalaman (`PHP 200.00`, hindi `₱200.00`): ang built-in na
// Helvetica ng `pdf` ay Latin-1 lang ang sakop at tahimik na tinatanggal ang
// `₱` — parehong dahilan ng komento sa `report_exporter.dart`.
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../../core/utils/timezone.dart';

final _money = NumberFormat('#,##0.00', 'en_PH');
final _stamp = DateFormat('MMM d, y h:mm a');

/// 'gcash_xendit' → 'GCash', 'office_cash' → 'Office', atbp. — kapareho ng
/// label na nakikita sa receipt card.
String paymentReceiptMethodLabel(String method) {
  switch (method) {
    case 'gcash':
    case 'gcash_xendit':
      return 'GCash';
    case 'office_cash':
    case 'cash':
      return 'Office';
    case 'rider_collection':
      return 'Rider Collection';
    default:
      return method.replaceAll('_', ' ');
  }
}

/// `verified` → 'PAID' (kapareho ng "Paid" na label sa UI).
String paymentReceiptStatusLabel(String status) {
  final low = status.toLowerCase();
  if (low == 'verified' || low == 'paid' || low == 'completed') return 'PAID';
  if (low == 'pending') return 'PENDING';
  if (low == 'reversed') return 'REVERSED';
  if (low == 'failed') return 'FAILED';
  return status.isEmpty ? 'RECORDED' : status.toUpperCase();
}

/// `Receipt-LN-2026-605277-JR-MVIOINWAEB.pdf` — safe na filename para sa
/// lahat ng platform (walang `/`, `:` o space).
String paymentReceiptFileName(Map<String, dynamic> data) {
  final loan = (data['loan_number'] as String?)?.trim() ?? '';
  final ref = (data['reference_number'] as String?)?.trim() ?? '';
  final parts = [
    if (loan.isNotEmpty) loan,
    if (ref.isNotEmpty) ref,
  ];
  final base = parts.isEmpty ? 'payment' : parts.join('-');
  final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
  return 'Receipt-$safe.pdf';
}

/// Buong printable na resibo — isang A5 page, sapat para sa print at PDF share.
Future<Uint8List> buildPaymentReceiptPdf(Map<String, dynamic> data) async {
  final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
  final status = data['status'] as String? ?? '';
  final method =
      paymentReceiptMethodLabel(data['payment_method'] as String? ?? '');
  final refNum = (data['reference_number'] as String?)?.trim() ?? '';
  final loanNum = (data['loan_number'] as String?)?.trim() ?? '';
  final paidAt = parseManilaValue(data['created_at']);

  pw.Widget row(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 130,
              child: pw.Text(label,
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700)),
            ),
            pw.Expanded(
              child: pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
      );

  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(26),
      build: (ctx) => [
        pw.Text('Jireta Loans & Credit Corp',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text('OFFICIAL PAYMENT RECEIPT',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 10),
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                      status.toLowerCase() == 'verified'
                          ? 'AMOUNT PAID'
                          : 'AMOUNT',
                      style: const pw.TextStyle(
                          fontSize: 8, color: PdfColors.grey700)),
                  pw.SizedBox(height: 2),
                  pw.Text('PHP ${_money.format(amount)}',
                      style: pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.Text(paymentReceiptStatusLabel(status),
                style:
                    pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(color: PdfColors.grey300),
        pw.SizedBox(height: 6),
        row('Loan Number', loanNum.isEmpty ? '-' : loanNum),
        row('Payment Method', method.isEmpty ? '-' : method),
        row('Reference No.', refNum.isEmpty ? '-' : refNum),
        if (paidAt != null) row('Date & Time', _stamp.format(paidAt)),
        pw.SizedBox(height: 12),
        pw.Divider(color: PdfColors.grey300),
        pw.SizedBox(height: 6),
        pw.Text('This receipt is an official record of your payment.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    ),
  );
  return doc.save();
}
