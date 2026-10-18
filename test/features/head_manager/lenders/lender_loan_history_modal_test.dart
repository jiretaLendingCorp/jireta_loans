// test/features/head_manager/lenders/lender_loan_history_modal_test.dart
//
// KASAYSAYAN NG LOAN NG KLIYENTE (admin / head manager)
//
// ANO ANG TINITIGNAN NITO
//   • May "View" button sa Previous Loans card ng Lender Details na nagbubukas
//     ng kompletong loan history ng kliyente.
//   • Kasama sa history ang LAHAT ng loan — dati at kasalukuyan — kaya kapag
//     bayad na at `completed` na ang loan, nakikita pa rin ito ng head manager
//     (hindi ito nawawala sa listahan).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/di/injection.dart';
import 'package:jireta_loans/data/datasources/remote/loan_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/head_manager/lenders/widgets/lender_loan_history_modal.dart';

class _FakeLoanDs implements LoanRemoteDataSource {
  final List<Map<String, dynamic>> rows;
  String? receivedLenderId;

  _FakeLoanDs(this.rows);

  @override
  Future<Map<String, dynamic>> getList({
    String? status,
    int page = 1,
    int limit = 20,
    String? search,
    String? lenderId,
    String? dateFrom,
    String? dateTo,
  }) async {
    receivedLenderId = lenderId;
    return {
      'data': rows,
      'meta': {'page': page, 'total_pages': 1, 'total': rows.length},
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _loan(
  String number,
  String status, {
  double principal = 10000,
  double? outstanding,
  String createdAt = '2026-09-01T02:00:00.000Z',
}) =>
    {
      'loan_number': number,
      'status': status,
      'principal_amount': principal,
      'outstanding_balance': outstanding,
      'payment_frequency': 'daily',
      'created_at': createdAt,
    };

Future<void> _pumpModal(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(
      body: Center(
        child: LenderLoanHistoryModal(
          lenderId: 'lender-1',
          lenderName: 'Mary Joy Gutierez',
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  late _FakeLoanDs fake;

  setUp(() async {
    fake = _FakeLoanDs([
      _loan('LN-2026-140800', 'active', outstanding: 7560),
      _loan('LN-2026-446486', 'completed', principal: 58685, outstanding: 0),
      _loan('LN-2026-111111', 'rejected', principal: 21000),
    ]);
    await sl.reset();
    sl.registerSingleton<LoanRemoteDataSource>(fake);
  });

  tearDown(() => sl.reset());

  testWidgets('kasama ang DATING at KASALUKUYANG loan — pati completed',
      (tester) async {
    await _pumpModal(tester);

    // Kumpleto ang history: ongoing, completed, at rejected.
    expect(find.text('LN-2026-140800'), findsOneWidget);
    expect(find.text('LN-2026-446486'), findsOneWidget);
    expect(find.text('LN-2026-111111'), findsOneWidget);

    // Nakikita pa rin ang bayad nang loan (completed).
    expect(find.text('Completed'), findsWidgets);
    expect(find.text('Fully paid'), findsOneWidget);

    // Walang status filter — buong history ng lender ang hinihingi.
    expect(fake.receivedLenderId, 'lender-1');
  });

  testWidgets('may empty state kapag wala pang loan ang kliyente',
      (tester) async {
    fake.rows.clear();
    await _pumpModal(tester);

    expect(find.text('No previous loans found'), findsOneWidget);
  });

  testWidgets('naka-wire ang "View" button sa Lender Details', (tester) async {
    final src = File(
      'lib/presentation/features/head_manager/lenders/screens/hm_lender_details_screen.dart',
    )
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    expect(src, contains("label: const Text('View')"));
    expect(src, contains('showHmLenderLoanHistoryModal('));
  });
}
