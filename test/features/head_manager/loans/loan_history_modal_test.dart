// test/features/head_manager/loans/loan_history_modal_test.dart
//
// PREVIOUS LOAN TAB → "View" (head manager)
//
// ANO ANG TINITIGNAN NITO
//   • Sa Previous Loan tab (`loan_history` URI), ang "View" ay nagbubukas ng
//     kasaysayan ng loan:
//     ang mga PAGBABAYAD (halaga, paraan, petsa at ORAS) at ang mga DATING
//     loan ng parehong kliyente.
//   • Nakikita pa rin ang bayad nang loan (completed) kasama ng iba pa.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/di/injection.dart';
import 'package:jireta_loans/data/datasources/remote/loan_remote_datasource.dart';
import 'package:jireta_loans/data/models/loan_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/loans/widgets/loan_history_modal.dart';

class _FakeLoanDs implements LoanRemoteDataSource {
  Map<String, dynamic> details;
  List<Map<String, dynamic>> clientLoans;
  String? receivedDetailsId;

  _FakeLoanDs({required this.details, this.clientLoans = const []});

  @override
  Future<Map<String, dynamic>> getDetails({required String loanId}) async {
    receivedDetailsId = loanId;
    return details;
  }

  @override
  Future<Map<String, dynamic>> getList({
    String? status,
    int page = 1,
    int limit = 20,
    String? search,
    String? lenderId,
    String? dateFrom,
    String? dateTo,
  }) async =>
      {
        'data': clientLoans,
        'meta': {'page': 1, 'total_pages': 1, 'total': clientLoans.length},
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LoanModel _loan({
  String status = 'active',
  double outstanding = 7000,
  double paymentsTotal = 4000,
}) =>
    LoanModel.fromJson({
      'id': 'loan-1',
      'loan_number': 'LN-2026-605277',
      'lender_id': 'lender-1',
      'lender_name': 'PrinCess Armalyn',
      'principal_amount': 10000,
      'interest_rate': 0,
      'interest_amount': 1000,
      'total_payable': 11000,
      'payments_total': paymentsTotal,
      'outstanding_balance': outstanding,
      'payment_frequency': 'daily',
      'term_days': 60,
      'term_periods': 60,
      'status': status,
      'created_at': '2026-09-21T10:51:00Z',
      'updated_at': '2026-10-12T07:42:00Z',
    });

Future<void> _pumpModal(WidgetTester tester, {LoanModel? loan}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(child: HmLoanHistoryModal(loan: loan ?? _loan())),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  late _FakeLoanDs fake;

  setUp(() async {
    fake = _FakeLoanDs(
      details: {
        'id': 'loan-1',
        'payments': [
          {
            'amount': 2500,
            'payment_method': 'gcash',
            'status': 'verified',
            'paid_at': '2026-10-12T07:42:00Z', // Manila: Oct 12, 2026 3:42 PM
            'xendit_reference': 'XND-998877',
          },
        ],
      },
      clientLoans: [
        // Kasalukuyang loan — hindi dapat maulit sa Previous Loans.
        {
          'id': 'loan-1',
          'loan_number': 'LN-2026-605277',
          'status': 'active',
          'principal_amount': 10000,
          'created_at': '2026-09-21T10:51:00Z',
        },
        // Dating loan, bayad na.
        {
          'id': 'loan-2',
          'loan_number': 'LN-2026-446486',
          'status': 'completed',
          'principal_amount': 58685,
          'created_at': '2026-09-27T07:18:00Z',
        },
      ],
    );
    await sl.reset();
    sl.registerSingleton<LoanRemoteDataSource>(fake);
  });

  tearDown(() => sl.reset());

  testWidgets('nakikita ang mga pagbabayad — halaga, paraan, petsa at ORAS',
      (tester) async {
    await _pumpModal(tester);

    expect(fake.receivedDetailsId, 'loan-1');
    // Isa sa payment row, isa sa "Total paid" footer ng table.
    expect(find.text('₱2,500.00'), findsNWidgets(2));
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('GCash'), findsOneWidget);
    // Eksaktong petsa at ORAS ng bayad (Manila).
    expect(find.text('Oct 12, 2026'), findsOneWidget);
    expect(find.text('3:42 PM'), findsOneWidget);
    expect(find.textContaining('XND-998877'), findsOneWidget);
    // May total row para madaling makita ang kabuuang bayad.
    expect(find.text('Total paid'), findsWidgets);
    // Wala nang Progress card sa summary (hiniling na tanggalin).
    expect(find.text('PROGRESS'), findsNothing);
    // English na ang copy ng modal.
    expect(find.text('Date, time, and amount of each payment'), findsOneWidget);
  });

  testWidgets('nakikita ang mga DATING loan — kasama ang completed',
      (tester) async {
    await _pumpModal(tester);

    expect(find.text('Previous Loans'), findsOneWidget);
    expect(find.text('LN-2026-446486'), findsOneWidget);
    expect(find.textContaining('Completed ·'), findsOneWidget);
    // Wala nang check icon sa loan rows.
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    // Hindi dapat maulit ang KASALUKUYANG (ongoing) loan sa Previous Loans.
    expect(find.text('LN-2026-605277'), findsNothing);
  });

  testWidgets('bayad nang loan (completed) ay kasama sa Previous Loans',
      (tester) async {
    // Kapag bayad na ang KASALUKUYANG loan, bahagi na ito ng kasaysayan —
    // hindi na dapat sabihing "walang previous loan".
    fake.clientLoans = [
      {
        'id': 'loan-1',
        'loan_number': 'LN-2026-605277',
        'status': 'completed',
        'principal_amount': 10000,
        'created_at': '2026-09-21T10:51:00Z',
      },
    ];
    final completed = _loan(
        status: 'completed', outstanding: 0, paymentsTotal: 11000);
    await _pumpModal(tester, loan: completed);

    expect(find.text('LN-2026-605277'), findsOneWidget);
    expect(find.text('1 loan'), findsOneWidget);
    // Wala nang "This loan" tag at status badge sa baba ng row.
    expect(find.text('This loan'), findsNothing);
    expect(find.textContaining('No other loans'), findsNothing);
  });

  testWidgets('completed loan pa rin ang nakikita kahit walang listahan',
      (tester) async {
    fake.clientLoans = const [];
    final completed = _loan(status: 'completed', outstanding: 0, paymentsTotal: 11000);
    await _pumpModal(tester, loan: completed);

    expect(find.text('LN-2026-605277'), findsOneWidget);
    expect(find.text('1 loan'), findsOneWidget);
  });

  testWidgets('ongoing na loan ay hindi inuulit sa Previous Loans',
      (tester) async {
    // Aktibo pa ang current loan — mga DATING loan lang ang nasa section.
    fake.clientLoans = [
      {
        'id': 'loan-1',
        'loan_number': 'LN-2026-605277',
        'status': 'active',
        'principal_amount': 10000,
        'created_at': '2026-09-21T10:51:00Z',
      },
    ];
    await _pumpModal(tester);

    expect(find.text('LN-2026-605277'), findsNothing);
    expect(find.text('0 loans'), findsOneWidget);
  });

  testWidgets('may mensahe kapag wala pang bayad', (tester) async {
    fake.details = {'id': 'loan-1', 'payments': const []};
    fake.clientLoans = const [];
    await _pumpModal(tester);

    expect(find.textContaining('No payments recorded'), findsOneWidget);
    expect(find.textContaining('No other loans'), findsOneWidget);
  });

  testWidgets('naka-wire ang "View" sa Previous Loan tab', (tester) async {
    final src = File(
      'lib/presentation/features/head_manager/loans/screens/hm_loan_applications_list_screen.dart',
    )
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    expect(src, contains('showHmLoanHistoryModal('));
    expect(src, contains('onTap: () => _openHistory(context, loan)'));
  });
}
