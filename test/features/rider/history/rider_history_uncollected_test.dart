// test/features/rider/history/rider_history_uncollected_test.dart
//
// FAILED COLLECTIONS SA RIDER HISTORY
//
//   * Wala nang "N failed" chip sa dashboard Total Collected card.
//   * Ang mga failed collection assignment ay lumalabas na sa History feed —
//     kasama ang completed — at "Uncollected" ang label (hindi "Failed"),
//     para hindi ito mapagkamalang nakolekta.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:jireta_loans/data/datasources/remote/ci_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/collection_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/disbursement_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/models/collection_assignment_model.dart';
import 'package:jireta_loans/presentation/features/rider/history/screens/rider_history_screen.dart';

import '../../../helpers/audit_test_helpers.dart';

Map<String, dynamic> _failedRow() => {
      'id': 'coll_failed_1',
      'status': 'failed',
      'loan_number': 'LN-2026-0042',
      'lender_name': 'Maria Santos',
      'requested_amount': 5000,
      'created_at': '2026-10-20T02:00:00Z',
      'collection_schedule': '2026-10-20',
    };

/// Ang `collections-get-list` ay isang status lang ang tinatanggap, kaya
/// hiwalay na tawag ang `completed` at `failed` — dito lang sa failed query
/// may laman ang sagot.
FakeDioClient _failedOnlyClient() => FakeDioClient((o) async {
      final status = o.queryParameters['status'];
      final isCollections = o.path.contains('collections-view');
      return Response<dynamic>(
        requestOptions: o,
        data: {
          'data': isCollections && status == 'failed' ? [_failedRow()] : <dynamic>[],
          'meta': {'unread_count': 0, 'total': 0},
          'total': 0,
        },
      );
    });

void main() {
  setUpAll(() async {
    await loadTestEnv();
    // Kailangan ng `toDateString()` (AppFormatters.date) sa history card.
    await initializeDateFormatting('en_PH');
  });

  setUp(() {
    GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
        () => NotificationRemoteDataSource(_failedOnlyClient()));
    GetIt.instance.registerLazySingleton<CollectionRemoteDataSource>(
        () => CollectionRemoteDataSource(_failedOnlyClient()));
    GetIt.instance.registerLazySingleton<CiRemoteDataSource>(
        () => CiRemoteDataSource(_failedOnlyClient()));
    GetIt.instance.registerLazySingleton<DisbursementRemoteDataSource>(
        () => DisbursementRemoteDataSource(_failedOnlyClient()));
  });

  tearDown(() => GetIt.instance.reset());

  test('statusLabel ng failed collection ay "Uncollected"', () {
    final model = CollectionAssignmentModel.fromJson(_failedRow());
    expect(model.statusLabel, 'Uncollected');
  });

  testWidgets('lumalabas sa History ang failed collection bilang Uncollected',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/rider/history',
      routes: [
        GoRoute(
          path: '/rider/history',
          builder: (_, __) => const RiderHistoryScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('Uncollected'), findsOneWidget);
    expect(find.text('Collection'), findsNothing);
    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('Loan #LN-2026-0042'), findsOneWidget);
  });
}
