// test/features/head_manager/collections/hm_collection_list_lendee_test.dart
//
// LENDEE COLUMN NG COLLECTIONS LIST (HM)
//
// Dati: "Lendee & Loan" ang column at LN ang primary text na nakalagay, tapos
// pangalan lang ng lendee sa ilalim.
//
// Ngayon: "Lendee" na lang ang column at pangalan ng lendee ang nakalagay —
// wala nang LN sa listahang ito (nasa Collection Details / Loan Records pa rin
// ito kapag kailangan).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/core/di/injection.dart';
import 'package:jireta_loans/data/datasources/remote/auth_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/collection_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/payment_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/data/models/collection_assignment_model.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/collections/providers/hm_collection_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/collections/screens/hm_collection_list_screen.dart';
import 'package:jireta_loans/presentation/features/head_manager/lenders/providers/hm_lender_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/profile/providers/hm_profile_provider.dart';
import 'package:jireta_loans/presentation/shared/providers/auth_state_provider.dart';

import '../../../helpers/audit_test_helpers.dart';

class DioClientFake extends FakeDioClient {
  DioClientFake()
      : super((o) async => Response<dynamic>(
              requestOptions: o,
              data: {
                'data': <dynamic>[],
                'items': <dynamic>[],
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

CollectionAssignmentModel _collection({
  String status = 'assigned',
  String lendee = 'PrinCess Armalyn',
  String loanNumber = 'LN-2026-605277',
}) =>
    CollectionAssignmentModel(
      id: 'col-1',
      loanScheduleId: 'sched-1',
      status: status,
      collectionType: 'rider',
      requestedAmount: 5000,
      createdAt: DateTime(2026, 10, 21, 8, 30),
      flatLoanNumber: loanNumber,
      flatLenderName: lendee,
      flatRiderName: 'Jay Shin',
      loanSchedule: {
        'loan': {'id': 'loan-1'},
        'amount_due': 5000,
      },
    );

class _StubCollectionNotifier extends HmCollectionNotifier {
  _StubCollectionNotifier(List<CollectionAssignmentModel> items)
      : super(CollectionRemoteDataSource(DioClientFake())) {
    state = HmCollectionState(items: items, totalCount: items.length);
  }

  @override
  Future<void> fetch({int page = 1, bool silent = false}) async {}
}

class _StubLenderNotifier extends HmLenderNotifier {
  _StubLenderNotifier() : super(UserRemoteDataSource(DioClientFake())) {
    state = const HmLenderState();
  }

  @override
  Future<void> load({bool silent = false}) async {}
}

/// Itinatala ang huling status na ipinasa sa server — para ma-verify na ang
/// "All Status" dropdown ay agad na nagfi-filter.
class _FakePaymentDs extends PaymentRemoteDataSource {
  _FakePaymentDs() : super(DioClientFake());

  String? lastStatus;
  String? lastMethod;

  @override
  Future<Map<String, dynamic>> getPaymentListPage({
    String? method,
    String? status,
    String? search,
    String? dateFrom,
    String? dateTo,
    int page = 1,
    int limit = 20,
  }) async {
    lastMethod = method;
    lastStatus = status;
    return {
      'data': <dynamic>[],
      'meta': {'page': 1, 'total_pages': 1, 'total': 0},
    };
  }
}

void main() {
  late _FakePaymentDs paymentDs;

  setUpAll(loadTestEnv);

  setUp(() async {
    sl.allowReassignment = true;
    await setupDependencies();
    // Ang payments tab ay hindi nire-render sa All tab, pero ini-instantiate
    // pa rin ito ng screen — gawing fake para walang totoong network call.
    paymentDs = _FakePaymentDs();
    sl.registerLazySingleton<PaymentRemoteDataSource>(() => paymentDs);
  });

  tearDown(() => GetIt.instance.reset());

  Future<_StubCollectionNotifier> pumpList(
    WidgetTester tester,
    CollectionAssignmentModel item, {
    String location = '/hm/collections',
  }) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/hm/collections',
          builder: (_, __) => const HmCollectionListScreen(),
        ),
        GoRoute(
          path: '/hm/collections/payments',
          builder: (_, __) => const HmCollectionListScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    final collection = _StubCollectionNotifier([item]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => _FakeAuthNotifier()),
        hmProfileProvider.overrideWith(
          (ref) => _FakeProfileNotifier(
            sl<UserRemoteDataSource>(),
            sl<AuthRemoteDataSource>(),
          ),
        ),
        hmCollectionProvider.overrideWith((ref) => collection),
        hmLenderProvider.overrideWith((ref) => _StubLenderNotifier()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return collection;
  }

  testWidgets('lendee lang ang nakalagay — walang LN sa row',
      (tester) async {
    await pumpList(tester, _collection());

    expect(tester.takeException(), isNull);

    // Naka-uppercase ang table headers (ResponsiveListCard).
    expect(find.text('LENDEE'), findsOneWidget,
        reason: 'Dapat "Lendee" na lang ang column header');
    expect(find.text('LENDEE & LOAN'), findsNothing);
    expect(find.text('PrinCess Armalyn'), findsOneWidget);
    expect(find.text('LN-2026-605277'), findsNothing,
        reason: 'Wala nang LN sa Collections list');
  });

  testWidgets('completed row: lendee pa rin ang nakalagay',
      (tester) async {
    await pumpList(tester, _collection(status: 'completed'));

    expect(tester.takeException(), isNull);
    expect(find.text('PrinCess Armalyn'), findsOneWidget);
    expect(find.text('LN-2026-605277'), findsNothing);
  });

  testWidgets('status filter: "All Status" dropdown sa toolbar',
      (tester) async {
    final collection = await pumpList(tester, _collection());

    expect(tester.takeException(), isNull);

    // Kapareho ng "All Riders" sa Rider Monitoring — dropdown sa toolbar.
    expect(find.text('All Status'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('Early Payers'), findsOneWidget);

    await tester.tap(find.text('All Status'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Completed').last);
    await tester.pumpAndSettle();

    expect(collection.state.statusFilter, 'completed',
        reason: 'Dapat agad na-filter sa Completed ang listahan');
    expect(find.text('Completed'), findsOneWidget,
        reason: 'Completed na ang nakalagay sa dropdown pagkatapos pumili');
  });

  testWidgets('Payments tab: lahat ng filter katabi ng search',
      (tester) async {
    await pumpList(tester, _collection(),
        location: '/hm/collections/payments');

    expect(tester.takeException(), isNull);
    expect(find.text('All Status'), findsOneWidget);
    expect(find.text('All Methods'), findsOneWidget);
    expect(find.text('Filter Date'), findsOneWidget);
    expect(find.textContaining('results'), findsOneWidget);

    // Isang row: pantay ang taas at nasa GILID ng search field.
    final rowDy = tester.getCenter(find.text('All Status')).dy;
    for (final label in ['All Methods', 'Filter Date']) {
      expect((tester.getCenter(find.text(label)).dy - rowDy).abs(),
          lessThan(4),
          reason: 'Dapat kapantay ng All Status ang "$label"');
    }
    expect(
      (tester.getCenter(find.textContaining('results')).dy - rowDy).abs(),
      lessThan(4),
      reason: 'Dapat kapantay ng All Status ang results chip',
    );
    expect(
      tester.getRect(find.text('Search payments...')).right,
      lessThan(tester.getTopLeft(find.text('All Status')).dx),
      reason: 'Dapat nasa gilid ng search ang lahat ng filter',
    );
    expect(tester.getTopLeft(find.text('All Methods')).dx,
        greaterThan(tester.getTopLeft(find.text('All Status')).dx));

    // Method dropdown: Office.
    await tester.tap(find.text('All Methods'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Office').last);
    await tester.pumpAndSettle();

    expect(paymentDs.lastMethod, 'office_cash',
        reason: 'Dapat na-filter sa Office ang payments');

    // Status dropdown: Paid.
    await tester.tap(find.text('All Status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paid').last);
    await tester.pumpAndSettle();

    expect(paymentDs.lastStatus, 'verified',
        reason: 'Dapat na-filter sa Paid ang payments');
  });
}
