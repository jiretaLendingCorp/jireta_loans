// test/features/head_manager/ci/hm_ci_list_actions_test.dart
//
// ACTIONS NG HM SA CREDIT INVESTIGATIONS TABLE.
//
// DATI: kahit anong status ng latest CI ay may "Assign/Reassign Rider" sa
// 3-dots menu — kaya kahit "Pending Approval" (hindi pa failed) ay may
// "Reassign Rider".
//
// NGAYON: Reassign lang kapag may failure na (failed / expired / declined).
// Aktibo, pending approval, approved, at rejected = View lang (plus
// Approve/Reject kapag pending).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/core/di/injection.dart';
import 'package:jireta_loans/data/datasources/remote/auth_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/ci_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/data/models/credit_investigation_model.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/ci/providers/hm_ci_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/ci/screens/hm_ci_list_screen.dart';
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

CreditInvestigationModel _ci(String status) => CreditInvestigationModel(
      id: 'ci-$status',
      loanId: 'loan-$status',
      status: status,
      createdAt: DateTime(2026, 10, 21, 8, 30),
      deadline: DateTime(2026, 10, 24),
      loan: {
        'loan_number': 'LN-2026-916379',
        'lender_profile': {
          'users': {'first_name': 'Mike', 'last_name': 'Nindo'},
        },
      },
      rider: {
        'users': {'first_name': 'Jay', 'last_name': 'Shin'},
      },
    );

class _StubHmCiNotifier extends HmCiNotifier {
  _StubHmCiNotifier(List<CreditInvestigationModel> items)
      : super(CiRemoteDataSource(DioClientFake())) {
    state = HmCiState(items: items, totalCount: items.length);
  }

  @override
  Future<void> fetch({int page = 1, bool silent = false}) async {}
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

  Future<void> pumpList(
    WidgetTester tester,
    CreditInvestigationModel ci,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/hm/ci',
      routes: [
        GoRoute(
            path: '/hm/ci', builder: (_, __) => const HmCiListScreen()),
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
        hmCiProvider.overrideWith((ref) => _StubHmCiNotifier([ci])),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('pending approval: walang Reassign Rider sa actions',
      (tester) async {
    await pumpList(tester, _ci('completed'));

    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Actions'));
    await tester.pumpAndSettle();

    expect(find.text('Reassign Rider'), findsNothing,
        reason: 'Hindi pa failed ang CI — wala pang reassignment');
    expect(find.text('Assign Rider'), findsNothing);
    expect(find.text('View'), findsOneWidget);
  });

  testWidgets('aktibong CI (in_progress): View lang, walang actions menu',
      (tester) async {
    await pumpList(tester, _ci('in_progress'));

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Actions'), findsNothing);
    expect(find.text('Reassign Rider'), findsNothing);
    expect(find.text('View'), findsOneWidget);
  });

  testWidgets('failed: may Reassign button', (tester) async {
    await pumpList(tester, _ci('failed'));

    expect(tester.takeException(), isNull);
    expect(find.text('Reassign'), findsOneWidget);
  });

  testWidgets('failed: "Not Completed" ang pill at row status, hindi "Failed"',
      (tester) async {
    await pumpList(tester, _ci('failed'));

    expect(tester.takeException(), isNull);
    expect(find.text('Not Completed'), findsOneWidget,
        reason: 'Pill label — hindi basta "Failed"');
    expect(find.text('Not Completed — Overdue'), findsOneWidget,
        reason: 'Row status — dapat pareho ang salita sa pill');
    expect(find.text('Failed'), findsNothing);
  });
}
