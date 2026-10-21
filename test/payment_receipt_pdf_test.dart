// test/payment_receipt_pdf_test.dart
//
// REGRESSION: walang printable na resibo sa lender Payment Receipt kapag
// `receipt_url` ay `null` (GCash/Xendit) — walang "Print Receipt" at walang
// "Download". Ang PDF builder na ito ang pinagmumulan ng ipiprinta, kaya
// sinusuri dito: (a) may valid na PDF bytes, (b) balanseng nilalaman/amount,
// at (c) malinis ang filename sa lahat ng platform.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/features/lender/payments/utils/payment_receipt_pdf.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import 'helpers/audit_test_helpers.dart';

Map<String, dynamic> _receipt({String? reference = 'JR-MVIOINWAEB'}) => {
      'receipt_url': null,
      'amount': 200.0,
      'payment_method': 'gcash_xendit',
      'status': 'verified',
      'reference_number': reference,
      'created_at': DateTime(2026, 10, 22, 6, 23),
      'loan_number': 'LN-2026-605277',
    };

/// Buong text ng unang page, naka-isang linya (`\s+` → space).
String _extract(Uint8List bytes) {
  final doc = sf.PdfDocument(inputBytes: bytes);
  final text = sf.PdfTextExtractor(doc).extractText();
  doc.dispose();
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

void main() {
  setUpAll(loadTestEnv);

  test('gumagawa ng valid na PDF na may tamang nilalaman', () async {
    final bytes = await buildPaymentReceiptPdf(_receipt());

    expect(bytes, isA<Uint8List>());
    expect(bytes.length, greaterThan(800));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');

    // Tunay na PDF: i-parse at i-extract ang text ng unang page. Bawat salita
    // ay hiwalay na linya sa extraction, kaya iniisa-isa muna ang whitespace.
    final word = _extract(bytes);

    expect(word, contains('Jireta Loans & Credit Corp'));
    expect(word, contains('OFFICIAL PAYMENT RECEIPT'));
    expect(word, contains('PHP 200.00'));
    expect(word, contains('PAID'));
    expect(word, contains('LN-2026-605277'));
    expect(word, contains('GCash'));
    expect(word, contains('JR-MVIOINWAEB'));
  });

  test('ASCII lang — walang ₱ na tinatanggal ng Helvetica', () async {
    final word = _extract(await buildPaymentReceiptPdf(_receipt()));

    expect(word, isNot(contains('₱')));
  });

  test('malinis ang filename kahit may espesyal na character', () {
    expect(paymentReceiptFileName(_receipt()),
        'Receipt-LN-2026-605277-JR-MVIOINWAEB.pdf');
    expect(
        paymentReceiptFileName({
          'loan_number': 'LN/2026 605277',
          'reference_number': 'JR:1',
        }),
        'Receipt-LN_2026_605277-JR_1.pdf');
    // Walang loan/reference: hindi blangkong pangalan.
    expect(paymentReceiptFileName(const {}), 'Receipt-payment.pdf');
  });

  test('mga label ng method at status', () {
    expect(paymentReceiptMethodLabel('gcash_xendit'), 'GCash');
    expect(paymentReceiptMethodLabel('office_cash'), 'Office');
    expect(paymentReceiptMethodLabel('rider_collection'), 'Rider Collection');
    expect(paymentReceiptStatusLabel('verified'), 'PAID');
    expect(paymentReceiptStatusLabel('pending'), 'PENDING');
    expect(paymentReceiptStatusLabel(''), 'RECORDED');
  });
}
