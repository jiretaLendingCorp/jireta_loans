// test/lender_payment_receipt_layout_test.dart
//
// Redesigned na Payment Receipt (lender): dapat walang overflow sa desktop at
// mobile, naka-center at may width limit sa desktop, at "Paid" ang label ng
// `verified` na bayad.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:jireta_loans/core/constants/route_constants.dart';
import 'package:jireta_loans/core/network/dio_client.dart';
import 'package:jireta_loans/data/datasources/remote/collection_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/payment_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/lender/payments/providers/lender_payment_provider.dart';
import 'package:jireta_loans/presentation/features/lender/payments/screens/lender_payment_receipt_screen.dart';

import 'helpers/audit_test_helpers.dart';

DioClient _offlineClient() => FakeDioClient((o) async => Response<dynamic>(
      requestOptions: o,
      data: {
        'data': <dynamic>[],
        'meta': {'unread_count': 0, 'total': 0},
      },
    ));

/// Receipt data lang ang kailangan — walang tunay na network.
class _StubPaymentNotifier extends LenderPaymentNotifier {
  _StubPaymentNotifier()
      : super(_StubPaymentDs(), CollectionRemoteDataSource(_offlineClient()));

  @override
  Future<Map<String, dynamic>> getReceiptData(String paymentId) async => {
        'receipt_url': null,
        'amount': 200.0,
        'payment_method': 'gcash_xendit',
        'status': 'verified',
        'reference_number': 'JR-MVCJ6VFSQ9',
        'created_at': DateTime(2026, 10, 17, 23, 8),
        'loan_number': 'LN-2026-605277',
      };
}

/// Hindi tinatawag sa receipt screen (override ang `getReceiptData`), pero
/// kailangan ng valid na instance.
class _StubPaymentDs extends PaymentRemoteDataSource {
  _StubPaymentDs() : super(_offlineClient());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('en_PH');
    await loadTestEnv();
    GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
        () => NotificationRemoteDataSource(_offlineClient()));
  });

  tearDownAll(() => GetIt.instance.reset());

  Future<void> pumpReceipt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: RouteConstants.lenderPaymentHistory,
      routes: [
        GoRoute(
          path: RouteConstants.lenderPaymentHistory,
          builder: (_, __) =>
              const LenderPaymentReceiptScreen(paymentId: 'pay_1'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        lenderPaymentProvider.overrideWith((ref) => _StubPaymentNotifier()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('desktop: naka-center, max 720, walang overflow', (tester) async {
    await pumpReceipt(tester, const Size(1366, 900));

    expect(tester.takeException(), isNull);
    final maxWidths = tester
        .widgetList<ConstrainedBox>(find.byType(ConstrainedBox))
        .map((b) => b.constraints.maxWidth)
        .toList();
    expect(maxWidths.contains(720.0), isTrue,
        reason: 'dapat naka-center/max-720 ang receipt sa desktop');

    // Nilalaman ng bagong receipt card.
    expect(find.text('Payment Successful'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget); // verified → Paid
    // Method chip sa amount block + Payment Method row.
    expect(find.text('GCash'), findsNWidgets(2));
    // GCash logo ang ginagamit, hindi generic na icon.
    expect(
      find.byWidgetPredicate((w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == 'assets/images/gcash.png'),
      findsOneWidget,
      reason: 'dapat naka-render ang assets/images/gcash.png sa receipt',
    );
    expect(find.text('JR-MVCJ6VFSQ9'), findsOneWidget);
    expect(find.text('LN-2026-605277'), findsOneWidget);
    expect(find.textContaining('200.00'), findsOneWidget);

    // REGRESSION: walang `receipt_url` (GCash/Xendit) → dating walang button sa
    // ilalim ng card. Dapat laging may "Download Receipt" (PDF ang ihahanda
    // kapag walang hosted receipt) — TEXT LINK at nasa LOOB ng card, sa ilalim
    // mismo ng "Date & Time". Walang "Print Receipt".
    expect(find.text('Download Receipt'), findsOneWidget);
    expect(find.text('Print Receipt'), findsNothing);

    final dateY = tester.getTopLeft(find.text('Date & Time')).dy;
    final downloadY = tester.getTopLeft(find.text('Download Receipt')).dy;
    expect(downloadY, greaterThan(dateY),
        reason: 'dapat nasa ilalim ng Date & Time ang Download Receipt');

    // Nasa loob ng receipt card (may clip + decoration na Container).
    final card = find.ancestor(
      of: find.text('Download Receipt'),
      matching: find.byWidgetPredicate(
          (w) => w is Container && w.clipBehavior == Clip.antiAlias),
    );
    expect(card, findsWidgets, reason: 'wala sa loob ng card ang link');
    final cardRect = tester.getRect(card.first);
    final downloadRect = tester.getRect(find.text('Download Receipt'));
    expect(downloadRect.top, greaterThan(cardRect.top));
    expect(downloadRect.bottom, lessThan(cardRect.bottom),
        reason: 'dapat nasa LOOB ng receipt card ang Download Receipt link');

    // Naka-tapat sa "Date & Time" — parehong kaliwang gilid ng icon (±2px),
    // kaya pantay ang hanay ng link at ng mga detalye.
    final rowIconLeft =
        tester.getTopLeft(find.byIcon(Icons.event_outlined)).dx;
    final linkIconLeft =
        tester.getTopLeft(find.byIcon(Icons.download_rounded)).dx;
    expect((linkIconLeft - rowIconLeft).abs(), lessThan(2.5),
        reason: 'hindi naka-tapat sa Date & Time ang Download Receipt link');
  });

  testWidgets('mobile: buong lapad, walang overflow', (tester) async {
    await pumpReceipt(tester, const Size(390, 844));

    expect(tester.takeException(), isNull);
    final maxWidths = tester
        .widgetList<ConstrainedBox>(find.byType(ConstrainedBox))
        .map((b) => b.constraints.maxWidth)
        .toList();
    expect(maxWidths.contains(720.0), isFalse,
        reason: 'walang 720 na limit sa mobile');
    expect(find.text('Payment Successful'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    // Download Receipt din sa mobile — hindi lang sa desktop.
    expect(find.text('Download Receipt'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Download Receipt')).dy,
        greaterThan(tester.getTopLeft(find.text('Date & Time')).dy));
  });
}
