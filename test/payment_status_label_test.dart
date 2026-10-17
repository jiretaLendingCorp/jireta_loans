// test/payment_status_label_test.dart
//
// Ang `payments.status = 'verified'` ay ipinapakita bilang **"Paid"** — bayad
// na ang ibig sabihin nito sa payment receipts/lists, hindi "Verified" na
// account o KYC document. Kinukumpirma rin dito na hindi nagbago ang label ng
// ibang status (pending / reversed) at na gumagana ang `labelOverride` ng
// `StatusBadge` (gamit sa receipt header).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/data/models/payment_model.dart';
import 'package:jireta_loans/presentation/shared/widgets/status_badge.dart';

void main() {
  group('payments: verified → Paid', () {
    test('paymentStatusLabel', () {
      expect(paymentStatusLabel('verified'), 'Paid');
      expect(paymentStatusLabel('VERIFIED'), 'Paid');
      // Ibang status: hindi ginalaw.
      expect(paymentStatusLabel('pending'), 'Pending');
      expect(paymentStatusLabel('reversed'), 'Reversed');
      expect(paymentStatusLabel('failed'), 'FAILED');
    });

    test('PaymentModel.statusLabel', () {
      final model = PaymentModel.fromJson({
        'id': 'pay_1',
        'loan_id': 'loan_1',
        'amount': 200,
        'payment_method': 'gcash_xendit',
        'status': 'verified',
      });
      expect(model.statusLabel, 'Paid');
    });

    testWidgets('StatusBadge labelOverride', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: StatusBadge(status: 'verified', labelOverride: 'Paid'),
        ),
      ));
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);
    });
  });
}
