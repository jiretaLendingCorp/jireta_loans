// test/lender_gcash_checkout_redirect_test.dart
//
// REGRESSION: "dapat dumideretso sa Xendit checkout link kapag magbabayad na
// si lender" — hindi ito nangyari dahil sa dalawang bagay:
//
//   1. KEY MISMATCH — ang Edge Function (`payments-xendit-link?fn=generate`) ay
//      `invoice_url` ang ibinabalik, pero `xendit_invoice_url` ang binabasa ng
//      app. Laging `null` ang URL: matagumpay ang server (may invoice at
//      `payments` row) pero "Failed to generate payment link" ang nakikita ng
//      lender at hindi kailanman nabubuksan ang hosted checkout page.
//   2. Walang pagbukas — kailangan pa ng pangalawang tap sa button. Ngayon,
//      awtomatikong binubuksan ang checkout pagkatapos ma-generate ang link, at
//      ipinapakita ang link kapag hinarang ito ng browser (popup blocker sa web)
//      o walang app na makakabukas.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/core/constants/route_constants.dart';
import 'package:jireta_loans/core/network/dio_client.dart';
import 'package:jireta_loans/data/datasources/remote/collection_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/payment_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/location_remote_datasource.dart';
import 'package:jireta_loans/presentation/shared/widgets/app_toast.dart';
import 'package:jireta_loans/presentation/features/lender/payments/providers/lender_payment_provider.dart';
import 'package:jireta_loans/presentation/features/lender/payments/screens/lender_pay_via_gcash_screen.dart';
import 'package:jireta_loans/presentation/features/lender/payments/screens/lender_payment_method_screen.dart';

import 'helpers/audit_test_helpers.dart';

const String _checkoutUrl = 'https://checkout.xendit.co/web/60f1a2b3c4d5e6f7';
const String _initiatedBanner =
    'Payment initiated. Your balance will update automatically once confirmed.';

/// Ang channel na ginagamit ng `url_launcher` (MethodChannelUrlLauncher). Hindi
/// ito nasasagot sa `flutter test`, kaya dati ay NAG-HANG ang `canLaunchUrl` —
/// kailangang i-mock para maging deterministiko ang test.
const MethodChannel _urlLauncherChannel =
    MethodChannel('plugins.flutter.io/url_launcher');

/// `DioClient` na walang network: tanging `get` ang kailangan ng list payload.
DioClient _offlineClient() => FakeDioClient((o) async => Response<dynamic>(
      requestOptions: o,
      data: {
        'data': <dynamic>[],
        'meta': {'unread_count': 0, 'total': 0},
      },
    ));

/// Datasource na nagbabalik ng eksaktong sagot ng Edge Function — walang Dio.
class _StubPaymentDs extends PaymentRemoteDataSource {
  _StubPaymentDs(this.linkResult) : super(_offlineClient());

  final Map<String, dynamic> linkResult;

  @override
  Future<Map<String, dynamic>> generateXenditLink({
    required String loanId,
    required String loanScheduleId,
  }) async =>
      linkResult;

  @override
  Future<Map<String, dynamic>> getPaymentListPage({
    String? method,
    String? status,
    String? search,
    String? dateFrom,
    String? dateTo,
    int page = 1,
    int limit = 20,
  }) async =>
      {
        'data': <dynamic>[],
        'meta': {'page': page, 'total_pages': 1, 'total': 0},
      };
}

/// Notifier na may nakapirming checkout URL — para ang widget test ay tumutok
/// sa redirect behavior ng screen, hindi sa network. Itinatala rin kung ilang
/// beses tinawag ang generate (para mapatunayang WALANG dobleng invoice).
class _StubGcashNotifier extends LenderPaymentNotifier {
  _StubGcashNotifier({this.url, this.error, this.completer})
      : super(
          _StubPaymentDs(const {}),
          CollectionRemoteDataSource(_offlineClient()),
        );

  final String? url;
  final String? error;

  /// Kapag ibinigay, hindi agad natatapos ang request (para ma-test ang
  /// "processing" na estado ng button).
  final Completer<String?>? completer;

  int calls = 0;

  @override
  Future<String?> generateGcashLink({
    required String loanId,
    required String loanScheduleId,
  }) {
    calls++;
    if (completer != null) return completer!.future;
    if (error != null) {
      // Kapareho ng ginagawa ng tunay na notifier: error sa state, null URL.
      state = state.copyWith(isSubmitting: false, error: error);
      return Future<String?>.value(null);
    }
    return Future<String?>.value(url);
  }
}

LenderPaymentNotifier _notifier(Map<String, dynamic> linkResult) =>
    LenderPaymentNotifier(
      _StubPaymentDs(linkResult),
      CollectionRemoteDataSource(_offlineClient()),
    );

/// Pekeng `url_launcher` platform: itinatala ang aktwal na binuksan.
class _FakeUrlLauncher {
  _FakeUrlLauncher({this.canLaunch = true, this.launchSucceeds = true});

  final bool canLaunch;
  final bool launchSucceeds;
  final List<String> launched = [];

  void install(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_urlLauncherChannel, (call) async {
      switch (call.method) {
        case 'canLaunch':
          return canLaunch;
        case 'launch':
          final args = call.arguments as Map<Object?, Object?>;
          launched.add(args['url']?.toString() ?? '');
          return launchSucceeds;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_urlLauncherChannel, null));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadTestEnv();
  });

  group('provider — ang invoice_url ng server ang ginagamit', () {
    test('binabasa ang `invoice_url` (hindi laging null)', () async {
      final notifier = _notifier({
        'invoice_url': _checkoutUrl,
        'xendit_invoice_id': 'inv_1',
        'payment_id': 'pay_1',
      });

      final url = await notifier.generateGcashLink(
        loanId: 'l1',
        loanScheduleId: 's1',
      );

      expect(url, _checkoutUrl);
      expect(notifier.state.xenditUrl, _checkoutUrl);
      expect(notifier.state.error, isNull);
    });

    test('lumang `xendit_invoice_url` key ay tinatanggap pa rin', () async {
      final url = await _notifier({'xendit_invoice_url': _checkoutUrl})
          .generateGcashLink(loanId: 'l1', loanScheduleId: 's1');
      expect(url, _checkoutUrl);
    });

    test('malinaw na error kapag walang checkout link ang server', () async {
      final notifier = _notifier(const {});
      final url = await notifier.generateGcashLink(
        loanId: 'l1',
        loanScheduleId: 's1',
      );

      expect(url, isNull);
      expect(notifier.state.error,
          'Xendit did not return a checkout link. Please try again.');
    });
  });

  group('screen — dere-derecho sa Xendit checkout', () {
    setUp(() {
      final client = _offlineClient();
      GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
          () => NotificationRemoteDataSource(client));
    });

    tearDown(() => GetIt.instance.reset());

    Future<void> pumpGcashScreen(WidgetTester tester, String? url) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Kailangan ang GoRouter: `GoRouterState.of(context)` ang gamit ng
      // `MobileScaffold` para sa route-aware chrome.
      final router = GoRouter(
        initialLocation: RouteConstants.lenderPayViaGcash,
        routes: [
          GoRoute(
            path: RouteConstants.lenderPayViaGcash,
            builder: (_, __) => const LenderPayViaGcashScreen(
              extra: {'loan_id': 'l1', 'schedule_id': 's1'},
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lenderPaymentProvider
                .overrideWith((ref) => _StubGcashNotifier(url: url)),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump(); // initState → Future.microtask(_generateLink)
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('awtomatikong binubuksan ang invoice_url ng Xendit',
        (tester) async {
      final launcher = _FakeUrlLauncher()..install(tester);

      await pumpGcashScreen(tester, _checkoutUrl);

      expect(tester.takeException(), isNull);
      // Hindi na kailangan ng pangalawang tap: nabuksan na ang checkout.
      expect(launcher.launched, [_checkoutUrl]);
      expect(find.text(_initiatedBanner), findsOneWidget);
      expect(find.text('Open Checkout Again'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      // Hindi na kailangan ang manwal na link kapag bumukas ang checkout.
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets('may manwal na link kapag hinarang ng browser ang pagbukas',
        (tester) async {
      final launcher =
          _FakeUrlLauncher(canLaunch: false)..install(tester);

      await pumpGcashScreen(tester, _checkoutUrl);

      expect(launcher.launched, isEmpty);
      expect(tester.takeException(), isNull);
      // Hindi dead-end: nasa screen pa rin ang eksaktong checkout link.
      expect(find.textContaining('use this secure link'), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        _checkoutUrl,
      );
      expect(find.text('Open Checkout'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('manwal na link din kapag bigo ang launch (popup blocker)',
        (tester) async {
      final launcher =
          _FakeUrlLauncher(launchSucceeds: false)..install(tester);

      await pumpGcashScreen(tester, _checkoutUrl);

      expect(launcher.launched, [_checkoutUrl]);
      expect(find.textContaining('use this secure link'), findsOneWidget);
      expect(find.text('Open Checkout'), findsOneWidget);
    });

    testWidgets('walang link kapag bigong bumuo ng checkout link',
        (tester) async {
      final launcher = _FakeUrlLauncher()..install(tester);

      await pumpGcashScreen(tester, null);

      expect(launcher.launched, isEmpty);
      expect(find.byType(SelectableText), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('Payment Method — isang tap lang, deretso checkout', () {
    late _StubGcashNotifier stub;

    setUp(() {
      final client = _offlineClient();
      stub = _StubGcashNotifier();
      final g = GetIt.instance;
      g.registerLazySingleton<DioClient>(() => client);
      g.registerLazySingleton<CollectionRemoteDataSource>(
          () => CollectionRemoteDataSource(client));
      g.registerLazySingleton<LocationRemoteDataSource>(
          () => LocationRemoteDataSource(client));
      g.registerLazySingleton<NotificationRemoteDataSource>(
          () => NotificationRemoteDataSource(client));
    });

    tearDown(() {
      AppToast.dismissAll();
      GetIt.instance.reset();
    });

    /// Pinupuno ang Payment Method screen at pinipili ang GCash — nasa "Pay
    /// via GCash" na ang button pagkatapos nito.
    Future<void> pumpMethodScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        initialLocation: RouteConstants.lenderPaymentMethod,
        routes: [
          GoRoute(
            path: RouteConstants.lenderPaymentMethod,
            builder: (_, __) => const LenderPaymentMethodScreen(
              extra: {
                'loan_id': 'l1',
                'schedule_id': 's1',
                'amount': 25200,
                'due_date': '2026-09-28',
              },
            ),
          ),
          GoRoute(
            path: RouteConstants.lenderPayViaGcash,
            builder: (_, state) => LenderPayViaGcashScreen(
              extra: (state.extra as Map<String, dynamic>?) ?? const {},
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lenderPaymentProvider.overrideWith((ref) => stub),
          ],
          // Panatilihing buhay ang (autoDispose) provider sa buong test — ito
          // ang totoong kondisyon ng app: may ibang screen (Payment Schedule,
          // history) na nakikinig dito, kaya hindi ito na-dispose sa gitna ng
          // async request.
          child: Consumer(
            builder: (context, ref, child) {
              ref.watch(lenderPaymentProvider);
              return MaterialApp.router(routerConfig: router);
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('GCash'));
      await tester.pump();
    }

    Future<void> tapPay(WidgetTester tester) async {
      await tester.tap(find.text('Pay via GCash'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    /// Pinapatay ang auto-dismiss timer ng toast para hindi maiwan na pending.
    Future<void> drainToast(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 3, milliseconds: 200));
    }

    testWidgets('processing ang button habang gumagawa ng invoice',
        (tester) async {
      _FakeUrlLauncher().install(tester);
      final completer = Completer<String?>();
      stub = _StubGcashNotifier(completer: completer);

      await pumpMethodScreen(tester);
      await tester.tap(find.text('Pay via GCash'));
      await tester.pump();

      // "May processing" — spinner sa button mismo, hindi bagong screen.
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text('Pay via GCash'), findsNothing);
      expect(find.byType(LenderPayViaGcashScreen), findsNothing);

      completer.complete(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await drainToast(tester);
    });

    testWidgets('deretso sa Xendit checkout pagkatapos ng isang tap',
        (tester) async {
      final launcher = _FakeUrlLauncher()..install(tester);
      stub = _StubGcashNotifier(url: _checkoutUrl);

      await pumpMethodScreen(tester);
      await tapPay(tester);

      expect(tester.takeException(), isNull);
      expect(stub.calls, 1);
      expect(launcher.launched, [_checkoutUrl]);
      // Walang intermediate na loading/GCash screen — deretso checkout.
      expect(find.byType(LenderPayViaGcashScreen), findsNothing);
      expect(
          find.text(
              'Xendit checkout opened. Please complete your GCash payment there.'),
          findsOneWidget);

      await drainToast(tester);
    });

    testWidgets('manwal na link kapag hinarang ng browser — isang invoice lang',
        (tester) async {
      final launcher = _FakeUrlLauncher(canLaunch: false)..install(tester);
      stub = _StubGcashNotifier(url: _checkoutUrl);

      await pumpMethodScreen(tester);
      await tapPay(tester);

      expect(launcher.launched, isEmpty);
      expect(find.byType(LenderPayViaGcashScreen), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        _checkoutUrl,
      );
      // Ang ipinasang URL ang ginamit — WALANG pangalawang invoice.
      expect(stub.calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(stub.calls, 1);
    });

    testWidgets('ipinapakita ang dahilan mula sa server kapag tumanggi',
        (tester) async {
      final launcher = _FakeUrlLauncher()..install(tester);
      stub = _StubGcashNotifier(
          error:
              "You've reached the limit of 3 GCash links for this installment. "
              'Please try again in about 30 minute(s).');

      await pumpMethodScreen(tester);
      await tapPay(tester);

      expect(launcher.launched, isEmpty);
      expect(find.byType(LenderPayViaGcashScreen), findsNothing);
      expect(find.textContaining('reached the limit of 3 GCash links'),
          findsOneWidget);
      // Bumalik sa normal ang button (hindi stuck sa processing).
      expect(find.text('Pay via GCash'), findsOneWidget);

      await drainToast(tester);
    });
  });
}
