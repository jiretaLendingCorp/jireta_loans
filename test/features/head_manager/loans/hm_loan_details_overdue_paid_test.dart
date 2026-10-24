// test/features/head_manager/loans/hm_loan_details_overdue_paid_test.dart
//
// "OVERDUE PAID" SA STATUS NG PAYMENT SCHEDULE (Loan Application Details)
//
// Ito ang screen na binuksan ng HM mula sa Loan Records. Kapag binayaran ang
// installment pagkalampas ng due date, "Overdue paid" ang dapat nakalagay sa
// Status — hindi lang "Paid" — para makita ng staff na nakabayad na ang lender
// sa dating overdue.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/data/datasources/remote/auth_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/loan_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/loans/providers/hm_loan_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/loans/screens/hm_loan_application_details_screen.dart';
import 'package:jireta_loans/presentation/features/head_manager/profile/providers/hm_profile_provider.dart';

import '../../../helpers/audit_test_helpers.dart';

Map<String, dynamic> _details() => {
      'id': 'loan-1',
      'loan_number': 'LN-2026-140800',
      'status': 'active',
      'principal_amount': 14000,
      'interest_amount': 2800,
      'total_payable': 16800,
      'outstanding_balance': 10500,
      'penalty_applied': false,
      'term_periods': 2,
      'installment_amount': 2100,
      'payment_frequency': 'daily',
      'created_at': '2026-09-29T21:32:00Z',
      'disbursement_method': 'rider_delivery',
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
        // On time → "Paid" pa rin.
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

class _FakeLoanDs extends LoanRemoteDataSource {
  _FakeLoanDs() : super(FakeDioClient((_) async => throw UnimplementedError()));

  @override
  Future<Map<String, dynamic>> getDetails({required String loanId}) async =>
      _details();

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
      {'data': const [], 'meta': const {'page': 1, 'total_pages': 1}};
}

class _FakeLoanNotifier extends HmLoanNotifier {
  _FakeLoanNotifier() : super(_FakeLoanDs());

  @override
  Future<void> fetchLoans({int page = 1, bool silent = false}) async {}
}

class _FakeUserDs extends UserRemoteDataSource {
  _FakeUserDs() : super(FakeDioClient((_) async => throw UnimplementedError()));
}

class _FakeAuthDs extends AuthRemoteDataSource {
  _FakeAuthDs() : super(FakeDioClient((_) async => throw UnimplementedError()));
}

class _FakeProfileNotifier extends HmProfileNotifier {
  _FakeProfileNotifier() : super(_FakeUserDs(), _FakeAuthDs());

  @override
  Future<void> loadProfile({bool silent = false}) async {
    state = HmProfileState(
      user: UserModel(
        id: 'hm-1',
        role: 'head_manager',
        firstName: 'Mylene',
        lastName: 'Cayabyab',
        accountStatus: 'active',
        forcePasswordChange: false,
        createdAt: DateTime.now(),
      ),
    );
  }
}

void main() {
  setUpAll(loadTestEnv);

  testWidgets('late-paid installment → "Overdue paid" sa Status',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const HmLoanApplicationDetailsScreen(loanId: 'loan-1'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        hmLoanProvider.overrideWith((ref) => _FakeLoanNotifier()),
        hmProfileProvider.overrideWith((ref) => _FakeProfileNotifier()),
      ],
      child: MaterialApp.router(routerConfig: router),
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
