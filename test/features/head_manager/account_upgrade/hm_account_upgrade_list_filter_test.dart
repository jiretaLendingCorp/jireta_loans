// test/features/head_manager/account_upgrade/hm_account_upgrade_list_filter_test.dart
//
// STATUS FILTER NG ACCOUNT UPGRADE (HM)
//
// Dati: nasa ITAAS ng search ang pills (All · Verified · Rejected) at may
// hiwalay pang "Pipeline" dropdown.
//
// Ngayon: isang "All Status" dropdown na katabi ng search sa toolbar —
// kapareho ng ginawa sa Payments at Collections (All Status · All Methods).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/core/di/injection.dart';
import 'package:jireta_loans/data/datasources/remote/account_upgrade_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/auth_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/data/models/account_upgrade_document_model.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/account_upgrade/providers/hm_account_upgrade_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/account_upgrade/screens/hm_account_upgrade_list_screen.dart';
import 'package:jireta_loans/presentation/features/head_manager/profile/providers/hm_profile_provider.dart';
import 'package:jireta_loans/presentation/shared/providers/auth_state_provider.dart';
import 'package:jireta_loans/presentation/shared/widgets/filter_pill_tab.dart';

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

AccountUpgradeDocumentModel _doc({String status = 'submitted'}) =>
    AccountUpgradeDocumentModel(
      id: 'doc-1',
      lenderId: 'lender-1',
      documentType: 'valid_id',
      status: status,
      createdAt: DateTime(2026, 9, 30, 6, 30),
      lender: {
        'first_name': 'Kim Bryan',
        'last_name': 'Galinato',
        'email': 'kim@gmail.com',
      },
      documentCount: 4,
    );

class _StubHmAccountUpgradeNotifier extends HmAccountUpgradeNotifier {
  _StubHmAccountUpgradeNotifier(List<AccountUpgradeDocumentModel> docs)
      : super(AccountUpgradeRemoteDataSource(DioClientFake())) {
    state = HmAccountUpgradeState(docs: docs, totalCount: docs.length);
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

  Future<_StubHmAccountUpgradeNotifier> pumpList(
    WidgetTester tester,
    AccountUpgradeDocumentModel doc,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/hm/account-upgrade',
      routes: [
        GoRoute(
          path: '/hm/account-upgrade',
          builder: (_, __) => const HmAccountUpgradeListScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    final notifier = _StubHmAccountUpgradeNotifier([doc]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => _FakeAuthNotifier()),
        hmProfileProvider.overrideWith(
          (ref) => _FakeProfileNotifier(
            sl<UserRemoteDataSource>(),
            sl<AuthRemoteDataSource>(),
          ),
        ),
        hmAccountUpgradeProvider.overrideWith((ref) => notifier),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return notifier;
  }

  testWidgets('All Status dropdown ay katabi ng search — walang pills sa itaas',
      (tester) async {
    await pumpList(tester, _doc());

    expect(tester.takeException(), isNull);

    expect(find.text('All Status'), findsOneWidget);
    expect(find.byType(FilterPillTab), findsNothing,
        reason: 'Wala nang hiwalay na pills row sa itaas ng search');

    // Parehong linya: All Status pagkatapos ng search, bago ang Filter Date.
    final search = tester.getRect(find.text('Search account upgrades...'));
    final status = tester.getRect(find.text('All Status'));
    final date = tester.getRect(find.text('Filter Date'));

    expect(status.left, greaterThan(search.right),
        reason: 'Dapat nasa gilid ng search ang All Status');
    expect((status.center.dy - search.center.dy).abs(), lessThan(4),
        reason: 'Dapat kapantay ng search ang All Status');
    expect(date.left, greaterThan(status.right),
        reason: 'All Status muna bago ang Filter Date');
  });

  testWidgets('pagpili ng Verified: agad na nagfi-filter ang listahan',
      (tester) async {
    final notifier = await pumpList(tester, _doc());

    expect(tester.takeException(), isNull);

    await tester.tap(find.text('All Status'));
    await tester.pumpAndSettle();

    // Bawat status ay option na ngayon sa iisang dropdown.
    expect(find.text('Submitted'), findsWidgets);
    expect(find.text('Rejected'), findsOneWidget);

    await tester.tap(find.text('Verified').last);
    await tester.pumpAndSettle();

    expect(notifier.state.statusFilter, 'verified',
        reason: 'Dapat Verified na ang ipinapasang status sa server');
    expect(find.text('Verified'), findsOneWidget,
        reason: 'Verified na ang nakalagay sa dropdown pagkatapos pumili');
  });
}
