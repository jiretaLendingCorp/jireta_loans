// test/features/shared/status_badge_visibility_test.dart
// Coverage para sa bug na paulit-ulit na lumalabas:
//   HINDI MABASA ANG STATUS SA DARK NA HEADER.
//
// Dalawang beses na itong nangyari:
//   • `overdue` (#B71C1C) sa dark hero ng loan details (#5C6370) — 1.7:1
//   • `reversed` sa payment receipt (dark navy gradient #0D1B2A) — sakop nito
//
// Ang dahilan: ang `StatusBadge` ay naglalagay ng semantic status color as-is,
// at ang status na WALANG sariling mapping ay bagsak sa default na gray
// (`AppColors.textSecondary` = #555568), na halos hindi makitang nakapatong sa
// dark na background. Ang lunas: `onDark: true` (puting bold na label) o
// `colorOverride`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Read a repo file and normalize line endings (Windows checkouts use CRLF).
String readNormalized(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

void main() {
  group('StatusBadge — may label at kulay ang `reversed`', () {
    test('`reversed` ay hindi na bagsak sa default gray/uppercase', () {
      final src = readNormalized('lib/presentation/shared/widgets/status_badge.dart');
      expect(src, contains("case 'reversed':"));
      // Parehong label ng `PaymentModel.statusLabel` — hindi uppercase default.
      expect(src, contains("return (AppColors.statusRejected, 'Reversed');"));
    });

    test('onDark ay pumipilit ng puting label (ginagamit ng dark headers)', () {
      final src = readNormalized('lib/presentation/shared/widgets/status_badge.dart');
      expect(src, contains('onDark ? Colors.white : (colorOverride ?? cfg.\$1)'));
    });
  });

  group('Dark hero cards — naka-onDark ang payment status badge', () {
    test('Lender payment receipt (dark navy gradient)', () {
      final src = readNormalized(
          'lib/presentation/features/lender/payments/screens/lender_payment_receipt_screen.dart');
      // Ang header ay lenderBlue → lenderBlueLight (#0D1B2A → #1A3658).
      expect(src, contains('AppColors.lenderBlue'));
      expect(src, contains('StatusBadge(status: status, onDark: true)'));
    });

    test('HM payment details (deepNavy hero card)', () {
      // Ang hero card ay nasa shared content widget na ngayon — parehong
      // ginagamit ng modal (View action) at ng `/hm/payments/:id` route.
      final src = readNormalized(
          'lib/presentation/features/head_manager/payments/widgets/payment_details_modal.dart');
      expect(src, contains('color: AppColors.deepNavy'));
      expect(src, contains('StatusBadge(status: status, onDark: true)'));
    });
  });
}
