// test/features/rider/quota/rider_my_quota_layout_test.dart
//
// LAYOUT NG "MY QUOTA" (/rider/my-quota)
//
// DATI: lahat naka-stack at nakaunat sa buong lapad ng browser. Sa desktop,
// ang tatlong metric (Confirmed / Remaining / Progress) at ang mga seksyon ay
// umaabot sa ~1100px — puno ng blangkong espasyo at mahirap basahin.
//
// NGAYON:
//   • Desktop (> 900px): may cap (1080) ang lapad at nakasentro; MAGKATABI ang
//     malaking target amount at ang tatlong metric, at MAGKATABI rin ang
//     "Collection history" at "Previous quotas".
//   • Mobile: naka-stack pa rin — walang lugar para sa dalawang column.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/data/datasources/remote/collection_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/models/rider_quota_model.dart';
import 'package:jireta_loans/presentation/features/rider/quota/providers/rider_quota_provider.dart';
import 'package:jireta_loans/presentation/features/rider/quota/screens/rider_my_quota_screen.dart';

import '../../../helpers/audit_test_helpers.dart';

DioClientFake _offlineClient() => DioClientFake();

/// `DioClient` na walang network — sapat na ang list payload.
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

RiderQuotaSelf _self() => RiderQuotaSelf(
      current: RiderQuota.fromJson({
        'quota_id': 'q1',
        'rider_id': 'r1',
        'period': 'weekly',
        'target_amount': 100000,
        'confirmed_collection': 25000,
        'remaining_target': 75000,
        'completion_percentage': 25,
        'start_date': '2026-10-19',
        'end_date': '2026-10-25',
        'status': 'active',
        'is_active': true,
        'achieved': false,
        'payment_count': 1,
      }),
      payments: [
        RiderQuotaPayment.fromJson({
          'payment_id': 'p1',
          'amount': 25000,
          'paid_at': '2026-10-20T10:00:00+08:00',
          'payment_method': 'office_cash',
          'loan_number': 'LN-2026-000001',
          'installment_number': 1,
        }),
      ],
      history: [
        RiderQuota.fromJson({
          'quota_id': 'q0',
          'rider_id': 'r1',
          'period': 'weekly',
          'target_amount': 80000,
          'confirmed_collection': 80000,
          'remaining_target': 0,
          'completion_percentage': 100,
          'start_date': '2026-10-12',
          'end_date': '2026-10-18',
          'status': 'completed',
          'is_active': false,
          'achieved': true,
          'payment_count': 3,
        }),
      ],
    );

/// Notifier na may nakapirming data — walang network sa test.
class _StubQuotaNotifier extends RiderQuotaNotifier {
  _StubQuotaNotifier(RiderQuotaSelf self)
      : super(CollectionRemoteDataSource(_offlineClient())) {
    state = RiderQuotaState(data: self);
  }

  @override
  Future<void> load({bool silent = false}) async {}
}

void main() {
  setUpAll(() async {
    await loadTestEnv();
  });

  setUp(() {
    GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
        () => NotificationRemoteDataSource(_offlineClient()));
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pumpQuota(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/rider/my-quota',
      routes: [
        GoRoute(
          path: '/rider/my-quota',
          builder: (_, __) => const RiderMyQuotaScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        riderQuotaProvider.overrideWith((ref) => _StubQuotaNotifier(_self())),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('desktop: cap ang lapad at magkatabi ang amount at metrics',
      (tester) async {
    await pumpQuota(tester, 1920);

    expect(tester.takeException(), isNull);
    expect(find.text('Weekly Collection Quota'), findsOneWidget);

    // May cap ang content sa desktop (hindi nakaunat sa 1920).
    final card = tester.getRect(find.text('Weekly Collection Quota'));
    expect(card.left, greaterThan(400),
        reason: 'Dapat nakasentro (may cap ang lapad) ang content sa desktop');

    // Magkatabi ang amount block at ang tatlong metric.
    final amount =
        tester.getCenter(find.textContaining('remaining to reach the target'));
    final confirmed = tester.getCenter(find.text('Confirmed'));
    // 280 (dating 300) — mas maluwag na 24px gutter ang desktop page, kaya
    // bahagya nang mas makitid ang card; magkatabi pa rin ang dalawa.
    expect(confirmed.dx, greaterThan(amount.dx + 280),
        reason: 'Dapat magkatabi (hindi naka-stack) ang metrics sa desktop');
    expect((confirmed.dy - amount.dy).abs(), lessThan(120));
  });

  testWidgets('desktop: magkatabi ang Collection history at Previous quotas',
      (tester) async {
    await pumpQuota(tester, 1920);

    final history = tester.getCenter(find.text('Collection history'));
    final previous = tester.getCenter(find.text('Previous quotas'));
    expect(previous.dx, greaterThan(history.dx + 200));
    expect((previous.dy - history.dy).abs(), lessThan(4),
        reason: 'Dapat magkapantay (side-by-side) ang dalawang seksyon');
  });

  testWidgets('mobile: naka-stack pa rin ang lahat', (tester) async {
    await pumpQuota(tester, 390);

    expect(tester.takeException(), isNull);

    final amount =
        tester.getCenter(find.textContaining('remaining to reach the target'));
    final confirmed = tester.getCenter(find.text('Confirmed'));
    expect(confirmed.dy, greaterThan(amount.dy + 40),
        reason: 'Naka-stack dapat ang metrics sa mobile');

    final history = tester.getCenter(find.text('Collection history'));
    final previous = tester.getCenter(find.text('Previous quotas'));
    expect(previous.dy, greaterThan(history.dy + 40),
        reason: 'Naka-stack dapat ang mga seksyon sa mobile');
  });
}
