// test/features/head_manager/loans/loan_details_schedule_status_test.dart
//
// "OVERDUE PAID" SA PAYMENT SCHEDULE (Loan Details side panel)
//
// Kapag binayaran ng lender ang installment pagkalampas ng due date, dapat
// "Overdue paid" ang Status nito — hindi lang "Paid" — para makita ng Head
// Manager (at Employee, parehong widget ang gamit) na may dating overdue na
// nabayaran.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/presentation/features/head_manager/loans/widgets/loan_details_side_panel.dart';

/// Katulad ng `loans-view?fn=get-details` payload (schedule rows ng
/// `v_loan_schedules`).
Map<String, dynamic> _details() => {
      'id': 'loan-1',
      'loan_number': 'LN-2026-140800',
      'status': 'active',
      'principal_amount': 14000,
      'interest_amount': 2800,
      'total_payable': 16800,
      'outstanding_balance': 12600,
      'penalty_applied': false,
      'term_periods': 2,
      'installment_amount': 2100,
      'payment_frequency': 'daily',
      'created_at': '2026-09-29T21:32:00Z',
      'lender': {'first_name': 'Mary Joy', 'last_name': 'Gutierrez'},
      'lender_profile': {'account_upgrade_status': 'verified'},
      'loan_schedules': [
        // Bayad ng Sep 27 ang due Sep 26 na installment → late paid.
        {
          'id': 'sched-1',
          'installment_number': 1,
          'due_date': '2026-09-26',
          'amount_due': 2100,
          'amount_paid': 2100,
          'status': 'paid',
          'paid_at': '2026-09-27T13:32:00Z',
        },
        // On time (bayad sa mismong due date) → "Paid" pa rin.
        {
          'id': 'sched-2',
          'installment_number': 2,
          'due_date': '2026-09-27',
          'amount_due': 2100,
          'amount_paid': 2100,
          'status': 'paid',
          'paid_at': '2026-09-27T01:00:00Z',
        },
      ],
      'payments': const [],
      'co_makers': const [],
      'credit_investigations': const [],
      'disbursements': const [],
      'penalties': const [],
    };

void main() {
  testWidgets('late-paid installment → "Overdue paid"; on-time → "Paid"',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LoanDetailsSidePanel(
          loanId: 'loan-1',
          loadDetails: (_) async => _details(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Overdue paid'), findsOneWidget,
        reason: 'Dapat may "Overdue paid" sa Status ng late-paid installment');
    // Kasama ang petsa ng bayad (Sep 27, 2026 sa Manila).
    expect(find.textContaining('Sep 27, 2026'), findsWidgets);
    expect(find.text('Paid'), findsWidgets,
        reason: 'On-time na installment ay "Paid" pa rin');
  });
}
