// test/features/head_manager/rider_monitoring/rider_monitoring_details_back_test.dart
//
// DETAILS PAGE NG RIDER MONITORING
//
//   • Nasa TOP BAR na ang Back button — dating nasa loob ng profile card
//     ("← Back to monitoring").
//   • "All dates" at "Available" ay plain text na — hindi na pill/button ang
//     itsura (dating may tinted background at rounded na 20 px radius).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:jireta_loans/data/datasources/remote/collection_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/models/rider_collection_monitoring_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_monitoring/providers/hm_rider_monitoring_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_monitoring/screens/hm_rider_monitoring_details_screen.dart';

import '../../../helpers/audit_test_helpers.dart';

class _OfflineDio extends FakeDioClient {
  _OfflineDio()
      : super((o) async => Response<dynamic>(
            requestOptions: o,
            data: {
              'data': <dynamic>[],
              'meta': {'unread_count': 0, 'total': 0},
            },
          ));
}

const _detail = RiderMonitoringDetail(
  rider: <String, dynamic>{
    'rider_name': 'Jay Shin',
    'phone_number': '09987654321',
    'plate_number': 'ABC-1234',
    'vehicle_type': 'Motorcycle',
    'is_available': true,
    'joined_at': '2026-09-23T00:00:00.000Z',
    'address': 'Purok 1, Naguilayan, San Carlos City, Pangasinan',
  },
  summary: RiderMonitoringSummary(
    expectedCollection: 70822,
    confirmedCollection: 75422,
    remainingDue: 0,
    assignedInstallments: 3,
  ),
);

class _StubDetail extends HmRiderMonitoringDetailNotifier {
  _StubDetail(RiderMonitoringDetailArgs args)
      : super(CollectionRemoteDataSource(_OfflineDio()), args) {
    state = const HmRiderMonitoringDetailState(detail: _detail);
  }

  @override
  Future<void> load({bool silent = false}) async {}
}

void main() {
  setUpAll(() async {
    await loadTestEnv();
    await initializeDateFormatting('en_PH', null);
    GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
      () => NotificationRemoteDataSource(_OfflineDio()),
    );
  });

  tearDownAll(() => GetIt.instance.reset());

  Future<void> pumpDetails(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/hm/rider-monitoring/r1',
      routes: [
        GoRoute(
          path: '/hm/rider-monitoring/:id',
          builder: (_, state) => HmRiderMonitoringDetailsScreen(
            riderId: state.pathParameters['id']!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hmRiderMonitoringDetailProvider
              .overrideWith((ref, args) => _StubDetail(args)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// May pill-like (rounded 20px + tinted) ancestor ba ang text?
  bool hasPillAncestor(WidgetTester tester, Finder finder) {
    return tester
        .widgetList<Container>(
          find.ancestor(of: finder, matching: find.byType(Container)),
        )
        .any((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.borderRadius == BorderRadius.circular(20);
    });
  }

  testWidgets('Back button ay nasa top bar, wala na sa card', (tester) async {
    await pumpDetails(tester);

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Back to monitoring'), findsNothing);
    // Profile card mismo ang nandiyan pa rin.
    expect(find.text('Jay Shin'), findsOneWidget);
  });

  testWidgets('"All dates" at "Available" ay plain text, hindi pill',
      (tester) async {
    await pumpDetails(tester);

    expect(find.text('All dates'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);

    expect(hasPillAncestor(tester, find.text('All dates')), isFalse,
        reason: 'Chip pa rin ang "All dates"');
    expect(hasPillAncestor(tester, find.text('Available')), isFalse,
        reason: 'Chip pa rin ang "Available"');
  });
}
