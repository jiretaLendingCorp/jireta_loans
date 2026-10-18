// test/rider_history_desktop_test.dart
//
// DESKTOP LAYOUT NG RIDER HISTORY (/rider/history)
//
// Dati, nakaunat sa buong browser width ang filter bar at ang history cards.
// Mula sa [kDesktopBreakpoint] pataas, naka-center na ang feed sa max na
// lapad (1240) at mas malaki ang gilid na padding — kapareho ng rider
// dashboard/profile. Sa mobile, buong lapad pa rin gaya dati.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/data/datasources/remote/ci_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/collection_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/disbursement_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/rider/history/screens/rider_history_screen.dart';

import 'helpers/audit_test_helpers.dart';

/// Walang network: sapat na ang empty list payload para sa history feed at sa
/// notification bell.
FakeDioClient _offlineClient() => FakeDioClient((o) async => Response<dynamic>(
      requestOptions: o,
      data: {
        'data': <dynamic>[],
        'meta': {'unread_count': 0, 'total': 0},
      },
    ));

void main() {
  setUpAll(() async {
    await loadTestEnv();
  });

  setUp(() {
    GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
        () => NotificationRemoteDataSource(_offlineClient()));
    GetIt.instance.registerLazySingleton<CollectionRemoteDataSource>(
        () => CollectionRemoteDataSource(_offlineClient()));
    GetIt.instance.registerLazySingleton<CiRemoteDataSource>(
        () => CiRemoteDataSource(_offlineClient()));
    GetIt.instance.registerLazySingleton<DisbursementRemoteDataSource>(
        () => DisbursementRemoteDataSource(_offlineClient()));
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pumpHistory(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
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
  }

  /// Ang ConstrainedBox na kumakapit sa feed (naka-ancestor ng filter bar).
  Finder contentBox() => find
      .ancestor(
        of: find.byType(DropdownButton<String?>),
        matching: find.byType(ConstrainedBox),
      )
      .first;

  group('Rider history desktop layout', () {
    testWidgets('1920px: naka-center at may max na lapad ang feed',
        (tester) async {
      await pumpHistory(tester, 1920);

      expect(tester.takeException(), isNull);

      final rect = tester.getRect(contentBox());
      expect(rect.width, 1240);

      // Naka-center sa loob ng content area (kanan ng 240px na sidebar), hindi
      // sa buong window.
      const contentCenter = (240 + 1920) / 2;
      expect(rect.center.dx, closeTo(contentCenter, 1),
          reason: 'Hindi naka-center ang history feed sa desktop');
    });

    testWidgets('390px: buong lapad pa rin (walang binago sa phone)',
        (tester) async {
      await pumpHistory(tester, 390);

      expect(tester.takeException(), isNull);
      expect(tester.getRect(contentBox()).width, 390);
    });
  });
}
