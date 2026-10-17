// test/lender_payment_history_layout_test.dart
//
// REGRESSION: ang Transaction (payment history) screen sa DESKTOP ay dating
// nakaunat sa buong browser width, at walang **GCash** filter kahit may GCash
// payments. Sinusuri dito:
//   * may desktop constraint (max 720) sa content, at
//   * ang GCash pill ay nagpapasa ng `method=gcash_xendit` sa listahan.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/core/constants/route_constants.dart';
import 'package:jireta_loans/core/network/dio_client.dart';
import 'package:jireta_loans/data/datasources/remote/collection_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/payment_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/lender/payments/providers/lender_payment_provider.dart';
import 'package:jireta_loans/presentation/features/lender/payments/screens/lender_payment_history_screen.dart';

import 'helpers/audit_test_helpers.dart';

/// Walang network: sapat na ang list payload para sa notification bell at sa
/// payment list.
DioClient _offlineClient() => FakeDioClient((o) async => Response<dynamic>(
      requestOptions: o,
      data: {
        'data': <dynamic>[],
        'meta': {'unread_count': 0, 'total': 0},
      },
    ));

/// Itinatala ang huling `method` na ipinasa ng screen, at nagbabalik ng isang
/// verified na GCash payment.
class _StubPaymentDs extends PaymentRemoteDataSource {
  _StubPaymentDs({this.reference = 'JR-MVCJ6VFSQ9'})
      : super(_offlineClient());

  /// Pwedeng napakahabang derived reference (hal. `...-SCHED-<uuid>` sa
  /// cash/office payments) — iyon ang dating nagpapa-overflow sa card.
  final String reference;
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
    return {
      'data': [
        {
          'id': 'pay_1',
          'loan_id': 'loan_1',
          'amount': 200,
          'payment_method': 'gcash_xendit',
          'status': 'verified',
          'reference_number': reference,
          'created_at': '2026-10-17T11:08:00+08:00',
          'loan': {'loan_number': 'LN-2026-605277'},
        }
      ],
      'meta': {'page': 1, 'total_pages': 1, 'total': 1},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('en_PH');
    await loadTestEnv();
  });

  setUp(() {
    GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
        () => NotificationRemoteDataSource(_offlineClient()));
  });

  tearDown(() => GetIt.instance.reset());

  Future<_StubPaymentDs> pumpHistory(
      WidgetTester tester, Size size,
      {_StubPaymentDs? stub}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ds = stub ?? _StubPaymentDs();
    final router = GoRouter(
      initialLocation: RouteConstants.lenderPaymentHistory,
      routes: [
        GoRoute(
          path: RouteConstants.lenderPaymentHistory,
          builder: (_, __) => const LenderPaymentHistoryScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        // Ang provider ay ginagamit ng screen; stub ang datasource para
        // walang tunay na network at para ma-record ang method filter.
        lenderPaymentProvider.overrideWith((ref) => LenderPaymentNotifier(
              ds,
              CollectionRemoteDataSource(_offlineClient()),
            )),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return ds;
  }

  testWidgets('desktop: naka-center (max 720) at may GCash filter',
      (tester) async {
    final ds = await pumpHistory(tester, const Size(1366, 900));

    expect(tester.takeException(), isNull);

    // Desktop layout: may ConstrainedBox na max 720 sa loob ng screen.
    final maxWidths = tester
        .widgetList<ConstrainedBox>(find.byType(ConstrainedBox))
        .map((b) => b.constraints.maxWidth)
        .toList();
    expect(maxWidths.contains(720.0), isTrue,
        reason: 'dapat naka-center/max-720 ang content sa desktop');

    // GCash brand asset — hindi fallback icon.
    final gcashLogo = find.byWidgetPredicate((w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == 'assets/images/gcash.png');
    expect(gcashLogo, findsWidgets,
        reason: 'dapat naka-render ang assets/images/gcash.png sa row');

    // Nasa tabi ng Cash on Delivery ang GCash pill.
    expect(find.text('Cash on Delivery'), findsWidgets);
    final gcashPill = find.widgetWithText(GestureDetector, 'GCash');
    expect(gcashPill, findsWidgets);

    await tester.tap(gcashPill.first);
    await tester.pump();

    expect(ds.lastMethod, 'gcash_xendit');
  });

  // Regression: ang mahabang reference ng cash/office payment
  // (`LN-…-SCHED-<uuid>`) ay nagpapa-overflow sa lumang card. Dapat ellipsis na
  // lang ito ngayon, walang overflow — kahit sa makitid na screen.
  testWidgets('mahabang reference: walang overflow (desktop at mobile)',
      (tester) async {
    const longRef =
        'LN-2026-605277-SCHED-5a1a96c3-1fd7-4675-86e9-3b5bf114150e-1792244';
    for (final size in const [Size(1366, 900), Size(390, 844)]) {
      await pumpHistory(tester, size, stub: _StubPaymentDs(reference: longRef));
      expect(tester.takeException(), isNull,
          reason: 'Nag-overflow sa ${size.width}px width');
      expect(find.textContaining(longRef), findsOneWidget);
    }
  });

  // Bago ang redesign, dalawang bahagi ang card (header + divider + amount row)
  // at madaling mag-overflow sa makitid na phone. Compact na row na ngayon —
  // sinusuri kung walang overflow at kumpleto pa rin ang impormasyon.
  testWidgets('mobile: walang overflow ang compact na transaction card',
      (tester) async {
    await pumpHistory(tester, const Size(390, 844));

    expect(tester.takeException(), isNull);
    expect(find.text('GCash'), findsWidgets);
    expect(find.text('Paid'), findsWidgets);
    // Loan number at reference ay magkasama na sa isang linya (ellipsis kapag
    // mahaba) para hindi mag-overflow.
    expect(find.textContaining('JR-MVCJ6VFSQ9'), findsOneWidget);
    expect(find.textContaining('LN-2026-605277'), findsOneWidget);
    expect(find.textContaining('200.00'), findsOneWidget);
  });
}
