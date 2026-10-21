// test/lender_payment_method_amount_test.dart
//
// Ang HALAGANG BABAYARAN ay dapat nakikita AT naipapasok ng lender sa Payment
// Method screen.
//
// Dati, ang screen na ito ay nagpapakita lang ng "Pay this installment via Cash
// on Delivery:" at ng mga paraan ng pagbabayad — hindi makita ang halaga, kaya
// kailangang bumalik pa sa Payment Schedule para tingnan ito. Ngayon, nasa
// pinakataas ang amount block, at EDITABLE ito para makapagbayad ng kahit
// magkano (partial / advance) — ang tinype ng lender ang ipinapadala sa
// collection request, hindi ang buong installment.
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
import 'package:jireta_loans/data/datasources/remote/payment_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/lender/payments/providers/lender_payment_provider.dart';
import 'package:jireta_loans/presentation/features/lender/payments/screens/lender_payment_method_screen.dart';
import 'package:jireta_loans/presentation/shared/widgets/app_toast.dart';

import 'helpers/audit_test_helpers.dart';

const _amountField = Key('payment_amount_field');

/// `DioClient` na walang network — sapat ang list payload ng mga datasource.
DioClient _offlineClient() => FakeDioClient((o) async => Response<dynamic>(
      requestOptions: o,
      data: {
        'data': <dynamic>[],
        'meta': {'unread_count': 0, 'total': 0},
      },
    ));

/// Notifier na nagtatala ng halagang ipinasa ng screen — walang network, kaya
/// ang ginagawa ng Pay button (halaga + validation) lang ang nasusubok.
class _StubPaymentNotifier extends LenderPaymentNotifier {
  _StubPaymentNotifier()
      : super(
          PaymentRemoteDataSource(_offlineClient()),
          CollectionRemoteDataSource(_offlineClient()),
        );

  int calls = 0;
  double? lastAmount;
  String? lastScheduleId;

  @override
  Future<bool> requestRiderCollection({
    required String loanScheduleId,
    double? amount,
  }) async {
    calls++;
    lastAmount = amount;
    lastScheduleId = loanScheduleId;
    return true;
  }
}

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
  // Ang success toast ay may 3s na timer — bawasan ito para walang pending
  // timer sa pagtatapos ng bawat test.
  tearDown(() => AppToast.dismissAll());

  String amountText(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(_amountField)).controller!.text;

  Future<void> pumpScreen(
    WidgetTester tester,
    double width,
    Map<String, dynamic> extra, {
    LenderPaymentNotifier? notifier,
  }) async {
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
        // Marker para sa STATUS na pupuntahan pagkatapos ng matagumpay na
        // submission (`/lender/payments` — Payment Schedule na may status chip).
        GoRoute(
          path: RouteConstants.lenderPayments,
          builder: (_, __) => const Scaffold(body: Text('payment status page')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (notifier != null)
            lenderPaymentProvider.overrideWith((ref) => notifier),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('mobile (390px): nakikita at naipapasok ang amount at due date',
      (tester) async {
    await pumpScreen(tester, 390, {
      'loan_id': 'l1',
      'schedule_id': 's1',
      'amount': 12500.5,
      'due_date': '2026-10-20',
    });

    expect(tester.takeException(), isNull);
    expect(find.text('Amount to Pay'), findsOneWidget);
    // Default: ang natitirang halaga ng installment, at EDITABLE ito.
    // AUTO PESO: naka-format agad na may thousand separators at 2 decimals.
    expect(amountText(tester), '12,500.50');
    expect(tester.widget<TextField>(find.byKey(_amountField)).readOnly, isFalse);
    expect(find.text('Due 2026-10-20'), findsOneWidget);
    // Malinaw kung magkano ang pwede at na pwedeng partial.
    expect(find.textContaining('You can pay any amount up to ₱12,500.50'),
        findsOneWidget);
    // Nasa ITAAS ng mga paraan ng pagbabayad ang amount.
    final amountY = tester.getCenter(find.byKey(_amountField)).dy;
    final methodY = tester.getCenter(find.text('Cash on Delivery')).dy;
    expect(amountY, lessThan(methodY),
        reason: 'Hindi nasa itaas ng mga method ang amount');

    // Nakakapag-type ng sariling halaga — auto-peso habang nagta-type.
    await tester.enterText(find.byKey(_amountField), '50000');
    await tester.pump();
    expect(amountText(tester), '50,000');
    await tester.enterText(find.byKey(_amountField), '50000.5');
    await tester.pump();
    expect(amountText(tester), '50,000.5');
    await tester.enterText(find.byKey(_amountField), '250');
    await tester.pump();
    expect(amountText(tester), '250');
    // Umalis ang focus → kumpletong 2 decimals (`250.00`).
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(amountText(tester), '250.00');

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
    expect(amountText(tester), '899.00');
    // Ang Pay button ay hindi nakaunat sa buong 1280px na screen.
    final buttonWidth = tester.getSize(find.byType(ElevatedButton)).width;
    expect(buttonWidth, lessThanOrEqualTo(760));

    await disposeTree(tester);
  });

  testWidgets('GCash ay selectable — walang "Coming Soon" badge', (tester) async {
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
    // Ang GCash ay laging buong installment ang sinisingil ng server, kaya
    // read-only ang amount doon (at nakabalik ito sa buong halaga).
    expect(amountText(tester), '25,200.00');
    expect(tester.widget<TextField>(find.byKey(_amountField)).readOnly, isTrue);
    expect(find.textContaining('GCash pays this installment in full'),
        findsOneWidget);

    // Bumalik sa Cash on Delivery → editable muli.
    await tester.tap(find.text('Cash on Delivery'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(_amountField)).readOnly, isFalse);

    await disposeTree(tester);
  });

  testWidgets('ang tinype na partial amount ang ipinapadala sa COD request',
      (tester) async {
    final stub = _StubPaymentNotifier();

    await pumpScreen(
      tester,
      390,
      {
        'loan_id': 'l1',
        'schedule_id': 's1',
        'amount': 2000,
        'outstanding_balance': 5000,
        'due_date': '2026-10-21',
      },
      notifier: stub,
    );

    await tester.enterText(find.byKey(_amountField), '750');
    await tester.pump();
    await tester.tap(find.text('Pay via Cash on Delivery'));
    await tester.pump();

    // Kumpirmasyon na may eksaktong halaga — hindi na kailangang hulaan.
    expect(find.textContaining('₱750.00'), findsWidgets);
    await tester.tap(find.text('Yes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Tapusin ang page transition ng `go` bago tingnan kung nawala na ang
    // Payment Method screen.
    await tester.pump(const Duration(milliseconds: 600));

    expect(stub.calls, 1);
    expect(stub.lastAmount, 750);
    expect(stub.lastScheduleId, 's1');

    // DERETSO SA STATUS: wala nang success dialog na nananatili sa Payment
    // Method screen — nakabukas na ang Payment Schedule kung saan makikita
    // ang status ng request.
    expect(find.text('payment status page'), findsOneWidget);
    expect(find.byType(LenderPaymentMethodScreen), findsNothing);
    expect(find.textContaining('₱750.00'), findsWidgets);

    // Patayin ang 3s na toast timer bago matapos ang test.
    await tester.pump(const Duration(seconds: 4));
    await disposeTree(tester);
  });

  testWidgets('hindi lalampas sa natitirang balanse ng loan', (tester) async {
    final stub = _StubPaymentNotifier();

    await pumpScreen(
      tester,
      390,
      {
        'loan_id': 'l1',
        'schedule_id': 's1',
        'amount': 2000,
        'outstanding_balance': 5000,
        'due_date': '2026-10-21',
      },
      notifier: stub,
    );

    // Ang buong loan balance (₱5,000) ang limitasyon, hindi lang ang ₱2,000 na
    // installment — kaya tinatanggap ang advance payment.
    await tester.enterText(find.byKey(_amountField), '4000');
    await tester.pump();

    // Sobra sa natitirang balanse → inline error, WALANG request.
    await tester.enterText(find.byKey(_amountField), '6000');
    await tester.pump();
    await tester.tap(find.text('Pay via Cash on Delivery'));
    await tester.pump();

    expect(find.text('The most you can pay is ₱5,000.00.'), findsOneWidget);
    expect(stub.calls, 0);
    expect(find.text('Yes'), findsNothing);

    await disposeTree(tester);
  });

  // ANG "Pay via GCash" FLOW AY NASubok NA SA IBANG FILE:
  // `test/lender_gcash_checkout_redirect_test.dart` — isang tap lang doon:
  // processing sa button, deretso sa Xendit checkout, at manwal na link na
  // fallback kapag hinarang ng browser. Dito ay layout/pagpili lang ng paraan.
}
