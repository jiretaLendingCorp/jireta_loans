// test/loan_overdue_paid_test.dart
//
// "OVERDUE PAID" SA LOAN RECORDS (HM + Employee)
//
// Kahit bayad na ng lender ang overdue niya, dapat MAKITA pa rin ng Head
// Manager at Employee na may dating overdue na nabayaran — at kailan.
//
//   • `overdue_paid_at` (mula sa `loans-view?fn=get-list`) = petsa ng huling
//     bayad na ginawa pagkalampas ng due date.
//   • `hasSettledOverdue` = may late payment AT wala nang overdue ngayon —
//     `false` kapag overdue pa rin ang loan (may natitira pang hindi bayad),
//     para hindi magmukhang bayad na ang hindi pa bayad.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/models/loan_model.dart';

LoanModel _loan({
  String status = 'active',
  double outstanding = 5000,
  String? overduePaidAt,
}) =>
    LoanModel.fromJson({
      'id': 'loan-1',
      'loan_number': 'LN-2026-760880',
      'lender_id': 'lender-1',
      'principal_amount': 50000,
      'interest_rate': 20,
      'interest_amount': 10000,
      'total_payable': 60000,
      'outstanding_balance': outstanding,
      'payment_frequency': 'monthly',
      'term_days': 30,
      'term_periods': 6,
      'status': status,
      'penalty_applied': false,
      'created_at': '2026-09-21T10:00:00Z',
      'updated_at': '2026-09-21T10:00:00Z',
      'overdue_paid_at': overduePaidAt,
      'lender_profile': {
        'users': {'first_name': 'April', 'last_name': 'Malasan'},
      },
    });

String _readNormalized(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');

void main() {
  group('LoanModel.overduePaidAt', () {
    test('binabasa ang overdue_paid_at bilang Manila date', () {
      final loan = _loan(overduePaidAt: '2026-09-27T13:32:00Z');
      expect(loan.overduePaidAt, isNotNull);
      // 1:32 PM UTC = 9:32 PM Manila — parehong araw pa rin.
      expect(loan.overduePaidAt!.year, 2026);
      expect(loan.overduePaidAt!.month, 9);
      expect(loan.overduePaidAt!.day, 27);
      expect(loan.overduePaidAt!.hour, 21);
    });

    test('null kapag wala pang late payment', () {
      expect(_loan().overduePaidAt, isNull);
    });
  });

  group('hasSettledOverdue (batayan ng tag sa row)', () {
    test('true kapag active at may late payment', () {
      expect(_loan(overduePaidAt: '2026-09-27T13:32:00Z').hasSettledOverdue,
          isTrue);
    });

    test('true kapag completed na (fully paid) at may late payment', () {
      expect(
          _loan(
            status: 'completed',
            outstanding: 0,
            overduePaidAt: '2026-09-27T13:32:00Z',
          ).hasSettledOverdue,
          isTrue);
    });

    test('false kapag overdue pa rin — may hindi pa bayad', () {
      expect(
          _loan(
            status: 'overdue',
            overduePaidAt: '2026-09-27T13:32:00Z',
          ).hasSettledOverdue,
          isFalse);
    });

    test('false kapag wala pang late payment', () {
      expect(_loan().hasSettledOverdue, isFalse);
    });
  });

  group('Naka-render ang tag sa Loan Records row (HM + Employee)', () {
    test('parehong screen ay may "Overdue paid" sa ilalim ng status', () {
      for (final path in const [
        'lib/presentation/features/head_manager/loans/screens/hm_loan_applications_list_screen.dart',
        'lib/presentation/features/employee/loans/screens/emp_loan_applications_screen.dart',
      ]) {
        final src = _readNormalized(path);
        expect(src, contains('loan.hasSettledOverdue'),
            reason: '$path: dapat may tag kapag bayad na ang overdue');
        expect(src, contains('Overdue paid · '),
            reason: '$path: "Overdue paid" na tag na may petsa ng bayad');
      }
    });
  });
}
