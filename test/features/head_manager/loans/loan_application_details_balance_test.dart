// test/features/head_manager/loans/loan_application_details_balance_test.dart
//
// REMAINING BALANCE sa Loan Application Details (HM).
//
// Ang `outstanding_balance` ay galing sa `loans-view?fn=get-details`
// (total payable + penalties − verified payments, hindi bababa sa 0). Sinusuri
// dito na NAKIKITA talaga ito sa screen — hindi lang nasa code — at ang tamang
// halaga ang naka-render.

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

/// Tugon ng `loans-view?fn=get-details` — pareho ng pinapadala ng server.
Map<String, dynamic> loanDetails({num outstanding = 16800}) => {
      'id': 'loan-1',
      'loan_number': 'LN-2026-140800',
      'status': 'overdue',
      'principal_amount': 14000,
      'interest_amount': 2800,
      'total_payable': 16800,
      'outstanding_balance': outstanding,
      'term_periods': 8,
      'installment_amount': 2100,
      'payment_frequency': 'daily',
      'created_at': '2026-09-29T21:32:00Z',
      'disbursement_method': 'rider_delivery',
      'lender': {'first_name': 'Mary Joy', 'last_name': 'Gutierrez'},
      'lender_profile': {'account_upgrade_status': 'verified'},
      'loan_schedules': const [],
      'payments': const [],
      'co_makers': const [],
      'credit_investigations': const [],
      'disbursements': const [],
      'penalties': const [],
    };

class _FakeLoanDs extends LoanRemoteDataSource {
  _FakeLoanDs()
      : super(FakeDioClient((_) async => throw UnimplementedError()));

  @override
  Future<Map<String, dynamic>> getDetails({required String loanId}) async =>
      loanDetails();

  // Kailangan ng notifier sa pagbuo nito (`fetchLoans()`).
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

  // Hindi kailangan ng listahan sa details screen.
  @override
  Future<void> fetchLoans({int page = 1, bool silent = false}) async {}
}

class _FakeUserDs extends UserRemoteDataSource {
  _FakeUserDs()
      : super(FakeDioClient((_) async => throw UnimplementedError()));
}

class _FakeAuthDs extends AuthRemoteDataSource {
  _FakeAuthDs()
      : super(FakeDioClient((_) async => throw UnimplementedError()));
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

Future<void> pumpDetails(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Kailangan ng GoRouter: ang sidebar ng WebScaffold ay nagbabasa ng
  // `GoRouterState.of(context)`.
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

  await tester.pumpWidget(ProviderScope(
    overrides: [
      hmLoanProvider.overrideWith((ref) => _FakeLoanNotifier()),
      hmProfileProvider.overrideWith((ref) => _FakeProfileNotifier()),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadTestEnv);

  testWidgets('nakikita ang Remaining Balance at ang tamang halaga',
      (tester) async {
    await pumpDetails(tester);

    // Nakalabas ang label sa stats sa itaas...
    expect(find.text('Remaining Balance'), findsOneWidget);
    // ...at ang halaga mula sa `outstanding_balance` (₱16,800.00).
    expect(find.text('₱16,800.00'), findsWidgets);

    // Kasama pa rin ang dating stats.
    expect(find.text('Principal'), findsOneWidget);
    expect(find.text('Total Payable'), findsOneWidget);
    expect(find.text('Term'), findsOneWidget);
  });
}
