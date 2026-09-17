// test/lender_payment_reference_test.dart
//
// REFERENCE NO. SA LENDER → TRANSACTION CARD
//
// TANONG: bakit "—" (gitling) ang Reference No. ng mga OFFICE payment?
//
// DAHILAN: ang office-cash payments ay walang reference number sa DB —
// ang `payments-manage?fn=record-office` ay loan/schedule/amount/notes lang
// ang kinukuha (walang OR/reference), at ang `reference_number` na ipinapasa
// ng `payments-view?fn=get-list` ay mula lang sa Xendit
// (`xendit_reference ?? xendit_payment_id`) kaya NULL ito para sa office cash.
//
// FIX (commit "disburse"): `PaymentModel.displayReference` ay nagde-derive ng
// stable na `JR-<payment id prefix>` kapag walang totoong reference — pareho
// ito sa receipt at sa HM/employee payment details, kaya hindi na "—".
// Ang card ay nag-“—” lang kapag WALANG id ang row (blangko talaga ang lahat).

import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/data/models/payment_model.dart';

/// Payload shape na ipinapadala ng `payments-view?fn=get-list`.
Map<String, dynamic> _payment({
  String? id,
  String? reference,
  String? idempotencyKey,
}) => {
      'id': id ?? '8f14e45f-ceea-467a-9b1b-0d5a1c2e3f40',
      'loan_id': 'loan-1',
      'loan_schedule_id': 'sched-1',
      'amount': 444.44,
      'method': 'office_cash',
      'payment_method': 'office_cash',
      'status': 'verified',
      'reference_number': reference,
      'xendit_payment_id': null,
      'xendit_reference': null,
      'idempotency_key': idempotencyKey,
      'created_at': '2026-09-17T08:31:00.000Z',
      'loan': {'loan_number': 'LN-2026-872871'},
    };

void main() {
  test('office cash na walang reference → JR-… (hindi "—")', () {
    final p = PaymentModel.fromJson(_payment());
    expect(p.referenceNumber, isNull);
    expect(p.displayReference, 'JR-8F14E45FCEEA',
        reason: 'derived na reference mula sa payment id');
  });

  test('may totoong reference (GCash/Xendit) → iyon ang ipinapakita', () {
    final p = PaymentModel.fromJson(_payment(reference: 'GC-1234567890'));
    expect(p.displayReference, 'GC-1234567890');
  });

  test('walang id → idempotency key ang fallback (hindi pa rin "-")', () {
    final p = PaymentModel.fromJson(
        _payment(id: '', idempotencyKey: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'));
    expect(p.displayReference, 'JR-A1B2C3D4E5F6',
        reason: 'office/rider cash ay may idempotency key mula sa client');
  });

  test('blangko lang kapag WALA talaga: id, reference at idempotency key', () {
    final p = PaymentModel.fromJson(_payment(id: '', idempotencyKey: ''));
    expect(p.displayReference, isEmpty);
  });

  test('maikling id (walang gitling) ay hindi pinutol', () {
    expect(PaymentModel.referenceFromId('abc123'), 'JR-ABC123');
  });
}
