// test/features/head_manager/loans/hm_loan_ongoing_actions_test.dart
//
// ACTIONS NG HM SA LOAN RECORDS TABLE
//
// Ongoing loan (`active`) = hindi na kailangan i-open ang buong details page;
// "View Remaining Balance" lang ang nasa 3-dots menu at compact na dialog ang
// lumalabas. Walang "Open details" sa menu sa LAHAT ng status — nasa row na
// mismo ang View action.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/core/di/injection.dart';
import 'package:jireta_loans/data/datasources/remote/auth_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/disbursement_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/in_office_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/loan_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/data/models/loan_model.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/disbursements/providers/hm_disbursement_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/in_office/providers/hm_in_office_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/loans/providers/hm_loan_history_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/loans/providers/hm_loan_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/loans/screens/hm_loan_applications_list_screen.dart';
import 'package:jireta_loans/presentation/features/head_manager/profile/providers/hm_profile_provider.dart';
import 'package:jireta_loans/presentation/shared/providers/auth_state_provider.dart';

import '../../../helpers/audit_test_helpers.dart';

class DioClientFake extends FakeDioClient {
  DioClientFake()
      : super((o) async => Response<dynamic>(
              requestOptions: o,
              data: {
                'data': <dynamic>[],
                'meta': {'unread_count': 0, 'total': 0},
              },
            ));
}

UserModel _headManager() => UserModel(
      id: 'hm-1',
      role: 'head_manager',
      firstName: 'Mylene',
      lastName: 'Cayabyab',
      accountStatus: 'active',
      forcePasswordChange: false,
      createdAt: DateTime.now(),
    );

class _FakeAuthNotifier extends AuthStateNotifier {
  _FakeAuthNotifier() {
    state = AuthState(isAuthenticated: true, user: _headManager());
  }
}

class _FakeProfileNotifier extends HmProfileNotifier {
  _FakeProfileNotifier(super.userDs, super.authDs);

  @override
  Future<void> loadProfile({bool silent = false}) async {
    state = HmProfileState(user: _headManager());
  }
}

LoanModel _loan(String status,
        {double outstanding = 5000, String? overduePaidAt}) =>
    LoanModel.fromJson({
      'id': 'loan-$status',
      'loan_number': 'LN-2026-760880',
      'lender_id': 'lender-1',
      'principal_amount': 50000,
      'interest_rate': 0.05,
      'interest_amount': 2500,
      'total_payable': 52500,
      'outstanding_balance': outstanding,
      'payment_frequency': 'monthly',
      'term_days': 30,
      'term_periods': 1,
      'status': status,
      'overdue_paid_at': overduePaidAt,
      'penalty_applied': false,
      'created_at': '2026-09-21T10:00:00Z',
      'updated_at': '2026-09-21T10:00:00Z',
      'lender_profile': {
        'users': {'first_name': 'April', 'last_name': 'Malasan'},
      },
    });

class _StubLoanNotifier extends HmLoanNotifier {
  _StubLoanNotifier(List<LoanModel> loans)
      : super(LoanRemoteDataSource(DioClientFake()), initialFilter: 'active') {
    state = HmLoanState(
      loans: loans,
      tabFilter: 'active',
      statusFilter: 'active',
      totalCount: loans.length,
    );
  }

  @override
  Future<void> fetchLoans({int page = 1, bool silent = false}) async {}
}

class _StubInOfficeNotifier extends HmInOfficeNotifier {
  _StubInOfficeNotifier()
      : super(InOfficeRemoteDataSource(DioClientFake()),
            LoanRemoteDataSource(DioClientFake()));

  @override
  Future<void> load(
      {String? status, int page = 1, bool silent = false}) async {}
}

class _StubDisbursementNotifier extends HmDisbursementNotifier {
  _StubDisbursementNotifier()
      : super(DisbursementRemoteDataSource(DioClientFake()));

  @override
  Future<void> load({bool silent = false}) async {}
}

class _StubHistoryNotifier extends HmLoanHistoryNotifier {
  _StubHistoryNotifier() : super(LoanRemoteDataSource(DioClientFake()));

  @override
  Future<void> load({int page = 1, bool silent = false}) async {}
}

void main() {
  setUpAll(loadTestEnv);

  setUp(() async {
    sl.allowReassignment = true;
    await setupDependencies();
    if (!GetIt.instance.isRegistered<NotificationRemoteDataSource>()) {
      GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
          () => NotificationRemoteDataSource(DioClientFake()));
    }
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pumpLoans(WidgetTester tester, LoanModel loan) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/hm/loan-records/ongoing',
      routes: [
        GoRoute(
          path: '/hm/loan-records/ongoing',
          builder: (_, __) => const HmLoanApplicationsListScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => _FakeAuthNotifier()),
        hmProfileProvider.overrideWith(
          (ref) => _FakeProfileNotifier(
            sl<UserRemoteDataSource>(),
            sl<AuthRemoteDataSource>(),
          ),
        ),
        hmLoanProvider.overrideWith((ref) => _StubLoanNotifier([loan])),
        hmInOfficeProvider.overrideWith((ref) => _StubInOfficeNotifier()),
        hmDisbursementProvider
            .overrideWith((ref) => _StubDisbursementNotifier()),
        hmLoanHistoryProvider.overrideWith((ref) => _StubHistoryNotifier()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('ongoing loan: View Remaining Balance, walang Open details',
      (tester) async {
    await pumpLoans(tester, _loan('active'));

    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();

    expect(find.text('View Remaining Balance'), findsOneWidget);
    expect(find.text('Open details'), findsNothing);
  });

  testWidgets('ongoing loan: compact na balanse ang binuksan', (tester) async {
    await pumpLoans(tester, _loan('active'));

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View Remaining Balance'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(find.text('Remaining Balance'), findsOneWidget);

    final lender =
        find.descendant(of: dialog, matching: find.text('April Malasan'));
    final loanNo =
        find.descendant(of: dialog, matching: find.text('LN-2026-760880'));
    expect(lender, findsOneWidget,
        reason: 'Dapat nakikita ang pangalan ng lender sa dialog');
    // Pangalan ng lender muna, tapos ang loan number sa ilalim.
    expect(
        tester.getTopLeft(lender).dy, lessThan(tester.getTopLeft(loanNo).dy));

    expect(find.textContaining('5,000'), findsWidgets);
    expect(find.text('Remaining balance on this ongoing loan'), findsOneWidget);
    expect(find.text('Total Payable'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);

    // X sa itaas ang pangsara — walang "Close" button sa ibaba.
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('bayad na ang overdue: "Overdue paid" tag sa ilalim ng status',
      (tester) async {
    await pumpLoans(
        tester, _loan('active', overduePaidAt: '2026-09-27T13:32:00Z'));

    expect(tester.takeException(), isNull,
        reason: 'Walang overflow sa fixed-height row');
    expect(find.text('Overdue paid · Sep 27, 2026'), findsOneWidget);
  });

  testWidgets('overdue pa rin: walang "Overdue paid" tag', (tester) async {
    await pumpLoans(
        tester, _loan('overdue', overduePaidAt: '2026-09-27T13:32:00Z'));

    expect(find.text('Overdue paid · Sep 27, 2026'), findsNothing);
  });

  testWidgets('walang late payment: walang "Overdue paid" tag', (tester) async {
    await pumpLoans(tester, _loan('active'));

    expect(find.textContaining('Overdue paid'), findsNothing);
  });

  // Walang "Open details" sa 3-dots menu kahit anong status — ang View action
  // sa row na ang paraan ng pagbukas ng details.
  for (final status in const [
    'pending',
    'under_review',
    'ci_required',
    'ci_assigned',
    'ci_completed',
    'approved',
    'active',
    'overdue',
    'completed',
  ]) {
    testWidgets('$status: walang Open details sa actions menu', (tester) async {
      await pumpLoans(tester, _loan(status, outstanding: 0));

      expect(tester.takeException(), isNull);

      final actions = find.byTooltip('Actions');
      if (actions.evaluate().isNotEmpty) {
        await tester.tap(actions);
        await tester.pumpAndSettle();
      }

      expect(find.text('Open details'), findsNothing);
      if (status != 'active') {
        expect(find.text('View Remaining Balance'), findsNothing);
      }
    });
  }
}
