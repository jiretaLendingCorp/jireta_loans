// test/rider_disbursement_list_desktop_test.dart
//
// CASH DELIVERIES LIST (/rider/disbursements) — DESKTOP LAYOUT
//
//   * Naka-center at may max na lapad (1240) ang feed — kapareho ng rider
//     dashboard/history. Dati, nakaunat ang card sa buong monitor.
//   * Makitid (320) at naka-align sa KANAN ang "Upload Cash on Delivery Proof"
//     button sa loob ng card; sa mobile, buong lapad pa rin.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/data/datasources/remote/disbursement_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/rider/disbursements/screens/rider_disbursement_list_screen.dart';

import 'helpers/audit_test_helpers.dart';

Map<String, dynamic> _pendingDisbursement() => {
      'id': 'd1',
      'loan_id': 'l1',
      'method': 'rider_delivery',
      'status': 'pending',
      'amount': 3500,
      'delivery_date': '2026-10-25',
      // Ang lender name ay galing sa `loan.lender_name` (tingnan ang
      // DisbursementModel.lenderName).
      'loan': {'loan_number': 'LN-2026-916379', 'lender_name': 'Mike Nindo'},
      'created_at': '2026-10-24T02:00:00Z',
    };

FakeDioClient _client() => FakeDioClient((o) async => Response<dynamic>(
      requestOptions: o,
      data: {
        'data': [if (o.path.contains('disbursements')) _pendingDisbursement()],
        'meta': {'unread_count': 0, 'total': 1},
      },
    ));

void main() {
  setUpAll(() async {
    await loadTestEnv();
  });

  setUp(() {
    GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
        () => NotificationRemoteDataSource(_client()));
    GetIt.instance.registerLazySingleton<DisbursementRemoteDataSource>(
        () => DisbursementRemoteDataSource(_client()));
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pumpList(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/rider/disbursements',
      routes: [
        GoRoute(
          path: '/rider/disbursements',
          builder: (_, __) => const RiderDisbursementListScreen(),
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

  testWidgets('1920px: naka-center at may max na lapad ang feed',
      (tester) async {
    await pumpList(tester, 1920);

    expect(tester.takeException(), isNull);
    expect(find.text('Loan LN-2026-916379'), findsOneWidget);
    expect(find.text('To: Mike Nindo'), findsOneWidget);

    final cap = find
        .byWidgetPredicate(
            (w) => w is ConstrainedBox && w.constraints.maxWidth == 1240)
        .first;
    final rect = tester.getRect(cap);
    expect(rect.width, 1240);

    // Naka-center sa loob ng content area (kanan ng 240px na sidebar).
    const contentCenter = (240 + 1920) / 2;
    expect(rect.center.dx, closeTo(contentCenter, 1),
        reason: 'Hindi naka-center ang deliveries feed sa desktop');

    // Makitid at naka-align sa KANAN ang Upload button sa loob ng card
    // (may 28px na feed padding + 16px na card padding sa gilid).
    final button = tester.getRect(find.byType(ElevatedButton));
    expect(button.width, 320);
    expect(rect.right - button.right, closeTo(44, 1));
  });

  testWidgets('390px: buong lapad pa rin ang feed at button', (tester) async {
    await pumpList(tester, 390);

    expect(tester.takeException(), isNull);
    final button = tester.getRect(find.byType(ElevatedButton));
    expect(button.width, closeTo(390 - 32 - 32, 2));
  });
}
