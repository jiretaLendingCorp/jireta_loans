// test/lender_payment_method_amount_test.dart
//
// Ang HALAGANG BABAYARAN ay dapat nakikita sa Payment Method screen.
//
// Dati, ang screen na ito ay nagpapakita lang ng "Pay this installment via Cash
// on Delivery:" at ng mga paraan ng pagbabayad — hindi makita ang halaga, kaya
// kailangang bumalik pa sa Payment Schedule para tingnan ito. Ngayon, nasa
// pinakataas ang amount card (halaga + due date).
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/core/constants/route_constants.dart';
import 'package:jireta_loans/core/network/dio_client.dart';
import 'package:jireta_loans/data/datasources/remote/collection_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/location_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/lender/payments/screens/lender_payment_method_screen.dart';

import 'helpers/audit_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestEnv();
    final client = FakeDioClient((o) async => Response<dynamic>(
          requestOptions: o,
          data: {
            'data': <dynamic>[],
            'meta': {'unread_count': 0, 'total': 0},
          },
        ));
    final g = GetIt.instance;
    g.registerLazySingleton<DioClient>(() => client);
    g.registerLazySingleton<CollectionRemoteDataSource>(
        () => CollectionRemoteDataSource(client));
    g.registerLazySingleton<LocationRemoteDataSource>(
        () => LocationRemoteDataSource(client));
    g.registerLazySingleton<NotificationRemoteDataSource>(
        () => NotificationRemoteDataSource(client));
  });

  tearDownAll(() => GetIt.instance.reset());

  Future<void> pumpScreen(
    WidgetTester tester,
    double width,
    Map<String, dynamic> extra,
  ) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: RouteConstants.lenderPaymentMethod,
      routes: [
        GoRoute(
          path: RouteConstants.lenderPaymentMethod,
          builder: (_, __) => LenderPaymentMethodScreen(extra: extra),
        ),
        // Marker lang para sa GCash (Xendit) destination — kapareho ng
        // convention sa ibang navigation test: hindi kailangan i-render ang
        // buong `LenderPayViaGcashScreen` (may sariling provider/network).
        GoRoute(
          path: RouteConstants.lenderPayViaGcash,
          builder: (_, __) => const Scaffold(body: Text('gcash page')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('mobile (390px): nakikita ang amount at due date',
      (tester) async {
    await pumpScreen(tester, 390, {
      'loan_id': 'l1',
      'schedule_id': 's1',
      'amount': 12500.5,
      'due_date': '2026-10-20',
    });

    expect(tester.takeException(), isNull);
    expect(find.text('Amount to Pay'), findsOneWidget);
    expect(find.text('₱12,500.50'), findsOneWidget);
    expect(find.text('Due 2026-10-20'), findsOneWidget);
    // Nasa ITAAS ng mga paraan ng pagbabayad ang amount.
    final amountY = tester.getCenter(find.text('₱12,500.50')).dy;
    final methodY = tester.getCenter(find.text('Cash on Delivery')).dy;
    expect(amountY, lessThan(methodY),
        reason: 'Hindi nasa itaas ng mga method ang amount');

    await disposeTree(tester);
  });

  testWidgets('desktop (1280px): naka-cap ang lapad, nakikita pa rin ang amount',
      (tester) async {
    await pumpScreen(tester, 1280, {
      'schedule_id': 's2',
      'amount': 899,
      'due_date': '2026-11-05',
    });

    expect(tester.takeException(), isNull);
    expect(find.text('₱899.00'), findsOneWidget);
    // Ang Pay button ay hindi nakaunat sa buong 1280px na screen.
    final buttonWidth = tester.getSize(find.byType(ElevatedButton)).width;
    expect(buttonWidth, lessThanOrEqualTo(760));

    await disposeTree(tester);
  });

  testWidgets('GCash ay selectable — walang "Coming Soon" badge',
      (tester) async {
    await pumpScreen(tester, 390, {
      'loan_id': 'l1',
      'schedule_id': 's1',
      'amount': 25200,
      'due_date': '2026-09-28',
    });

    expect(tester.takeException(), isNull);
    // Wala nang "Coming Soon" chip, at nandoon pa rin ang GCash card.
    expect(find.text('Coming Soon'), findsNothing);
    expect(find.text('GCash'), findsOneWidget);
    // Brand asset ang ginagamit sa GCash card, hindi generic na icon.
    expect(
      find.byWidgetPredicate((w) =>
          w is Image &&
          w.image is AssetImage &&
          (w.image as AssetImage).assetName == 'assets/images/gcash.png'),
      findsOneWidget,
      reason: 'dapat naka-render ang assets/images/gcash.png sa GCash card',
    );
    // Default pa rin ang Cash on Delivery.
    expect(find.text('Pay via Cash on Delivery'), findsOneWidget);

    // Napipili na ang GCash → nagbabago ang Pay button.
    await tester.tap(find.text('GCash'));
    await tester.pump();
    expect(find.text('Pay via GCash'), findsOneWidget);
    expect(find.text('Pay via Cash on Delivery'), findsNothing);

    await disposeTree(tester);
  });

  // ANG "Pay via GCash" FLOW AY NASubok NA SA IBANG FILE:
  // `test/lender_gcash_checkout_redirect_test.dart` — isang tap lang doon:
  // processing sa button, deretso sa Xendit checkout, at manwal na link na
  // fallback kapag hinarang ng browser. Dito ay layout/pagpili lang ng paraan.
}
