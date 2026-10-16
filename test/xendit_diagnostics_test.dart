// test/xendit_diagnostics_test.dart
//
// Coverage para sa XENDIT SANDBOX DIAGNOSTICS (Head Manager Settings):
//   1. Ang mga endpoint ay tumutugma sa `?fn=` router ng `payments-xendit-link`.
//   2. Ang datasource ay nagpapadala ng tamang path/body at ng
//      `x-idempotency-key` para hindi madoble ang test payment.
//   3. Ang card ay malinaw na naghihiwalay ng (a) connectivity, (b) payment
//      request creation, at (c) Xendit-confirmed payment.
//   4. HINDI kailanman nasa client bundle ang secret key, at ang server-side
//      guards (HEAD MANAGER-only, test-key-only, webhook token) ay naroroon.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:jireta_loans/core/errors/app_exception.dart';
import 'package:jireta_loans/core/network/api_endpoints.dart';
import 'package:jireta_loans/core/network/dio_client.dart';
import 'package:jireta_loans/core/utils/helpers.dart';
import 'package:jireta_loans/data/datasources/remote/payment_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/head_manager/settings/widgets/xendit_diagnostics_card.dart';

import 'helpers/audit_test_helpers.dart';

const String _paymentRequestId = 'pr-11111111-2222-3333-4444-555555555555';

Map<String, dynamic> _responseFor(String path) {
  if (path == ApiEndpoints.paymentsXenditDiagnostics) {
    return {
      'check': 'xendit_connectivity',
      'status': 'connected',
      'authenticated': true,
      'key_present': true,
      'key_preview': 'xnd_development_***4f60',
      'environment': 'test',
      'api_version': '2024-11-11',
      'endpoint': 'GET /v3/payment_requests/pr-00000000-0000-0000-0000-000000000000',
      'http_status': 404,
      'error_code': 'DATA_NOT_FOUND',
      'latency_ms': 120,
      'message': 'Authenticated with Xendit.',
      'warning': null,
      'checked_at': '2026-10-17T00:00:00.000Z',
      'sandbox_test_ready': true,
    };
  }
  if (path == ApiEndpoints.paymentsXenditTestCreate) {
    return {
      'payment_request_id': _paymentRequestId,
      'reference_id': 'JR-TEST-abc',
      'status': 'REQUIRES_ACTION',
      'amount': 100,
      'currency': 'PHP',
      'channel_code': 'GCASH',
      'duplicate': false,
      'actions': [
        {
          'type': 'REDIRECT_CUSTOMER',
          'descriptor': 'WEB_URL',
          'value': 'https://checkout.xendit.co/x',
        },
      ],
    };
  }
  if (path == ApiEndpoints.paymentsXenditTestStatus) {
    return {
      'check': 'xendit_test_payment_status',
      'test_payment': true,
      'payment_request_id': _paymentRequestId,
      'reference_id': 'JR-TEST-abc',
      'status': 'SUCCEEDED',
      'currency': 'PHP',
      'request_amount': 100,
      'terminal': true,
      'payment_confirmed': true,
      'recorded': true,
    };
  }
  if (path == ApiEndpoints.paymentsXenditTestSimulate) {
    return {
      'check': 'xendit_test_payment_simulation',
      'test_payment': true,
      'payment_request_id': _paymentRequestId,
      'amount': 100,
      'currency': 'PHP',
      'status': 'PENDING',
      'message': 'A simulated payment is being processed.',
      'payment_confirmed': false,
    };
  }
  return {};
}

/// [DioClient] na nagtatala ng lahat ng tawag at hindi kailanman nag-network.
class _RecordingDioClient extends DioClient {
  final List<RequestOptions> calls = [];
  final Set<String> seenIdempotencyKeys = {};
  Object? throwOn;

  Response<dynamic> _respond(RequestOptions options, String path) {
    calls.add(options);
    final throwError = throwOn;
    if (throwError != null) {
      throw DioException(
        requestOptions: options,
        message: 'Xendit rejected the credentials (401).',
        error: const UnauthorizedException('Xendit rejected the credentials (401).'),
      );
    }
    final payload = Map<String, dynamic>.from(_responseFor(path));
    if (path == ApiEndpoints.paymentsXenditTestCreate) {
      final key = options.headers['x-idempotency-key']?.toString() ?? '';
      // Idempotency: kaparehong key → kaparehong payment request, `duplicate`.
      if (!seenIdempotencyKeys.add(key)) {
        payload['duplicate'] = true;
      }
    }
    return Response<dynamic>(
      requestOptions: options,
      data: payload,
      statusCode: 200,
    );
  }

  @override
  Future<Response<dynamic>> post(
    String path, {
    dynamic data,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    return _respond(
      RequestOptions(
        path: path,
        method: 'POST',
        data: data,
        headers: headers ?? {},
      ),
      path,
    );
  }

  @override
  Future<Response<dynamic>> postWithIdempotency(
    String path, {
    required dynamic data,
    required String idempotencyKey,
  }) async {
    return _respond(
      RequestOptions(
        path: path,
        method: 'POST',
        data: data,
        headers: {'x-idempotency-key': idempotencyKey},
      ),
      path,
    );
  }
}

Finder _selectable(String text) => find.byWidgetPredicate(
      (w) => w is SelectableText && (w.data ?? '') == text,
    );

Future<void> _pumpCard(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: XenditDiagnosticsCard()),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Isang tap + dalawang pump: hindi `pumpAndSettle` dahil patuloy na
/// umiikot ang progress indicator habang `busy`.
Future<void> _tapAndSettle(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
}

void main() {
  setUpAll(() async => loadTestEnv());

  group('ApiEndpoints — Xendit sandbox diagnostics', () {
    test('gumagamit ng payments-xendit-link router (?fn=)', () {
      expect(ApiEndpoints.paymentsXenditDiagnostics,
          'payments-xendit-link?fn=diagnostics');
      expect(ApiEndpoints.paymentsXenditTestCreate,
          'payments-xendit-link?fn=create-test-payment');
      expect(ApiEndpoints.paymentsXenditTestStatus,
          'payments-xendit-link?fn=test-payment-status');
      expect(ApiEndpoints.paymentsXenditTestSimulate,
          'payments-xendit-link?fn=simulate-test-payment');
      // Ang existing (legacy) generate action ay hindi dapat nagbago.
      expect(ApiEndpoints.paymentsGenerateXenditLink,
          'payments-xendit-link?fn=generate');
    });

    test('idempotency key generator ay ang pinagsasaluhang helper', () {
      final a = AppHelpers.generateIdempotencyKey();
      final b = AppHelpers.generateIdempotencyKey();
      expect(a, isNot(equals(b)));
      expect(RegExp(r'^[A-Za-z0-9_-]{8,100}$').hasMatch(a), isTrue,
          reason: 'dapat pumasa sa normalizeIdempotencyKey ng Edge Function');
    });
  });

  group('PaymentRemoteDataSource — xendit diagnostics', () {
    late _RecordingDioClient client;
    late PaymentRemoteDataSource ds;

    setUp(() {
      client = _RecordingDioClient();
      ds = PaymentRemoteDataSource(client);
    });

    test('checkXenditConnectivity POSTs sa diagnostics at hindi nagbabago', () async {
      final data = await ds.checkXenditConnectivity();
      expect(client.calls.single.path, ApiEndpoints.paymentsXenditDiagnostics);
      expect(client.calls.single.method, 'POST');
      expect(data['status'], 'connected');
      expect(data['sandbox_test_ready'], isTrue);
    });

    test('createXenditTestPayment ay may x-idempotency-key at PHP body', () async {
      await ds.createXenditTestPayment(
        amount: 100,
        idempotencyKey: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        channelCode: 'GCASH',
      );
      final call = client.calls.single;
      expect(call.path, ApiEndpoints.paymentsXenditTestCreate);
      expect(call.headers['x-idempotency-key'],
          'a1b2c3d4-e5f6-7890-abcd-ef1234567890');
      expect((call.data as Map)['amount'], 100);
      expect((call.data as Map)['channel_code'], 'GCASH');
      // Walang secret key sa anumang client-side payload.
      expect(call.data.toString().toLowerCase().contains('secret'), isFalse);
      expect(call.data.toString().contains('xnd_'), isFalse);
    });

    test('getXenditTestPaymentStatus ay nagpapadala ng payment_request_id',
        () async {
      final data =
          await ds.getXenditTestPaymentStatus(paymentRequestId: _paymentRequestId);
      expect(client.calls.single.path, ApiEndpoints.paymentsXenditTestStatus);
      expect((client.calls.single.data as Map)['payment_request_id'],
          _paymentRequestId);
      expect(data['payment_confirmed'], isTrue);
    });

    test('simulateXenditTestPayment ay nagpapadala ng amount', () async {
      await ds.simulateXenditTestPayment(
          paymentRequestId: _paymentRequestId, amount: 100);
      expect(client.calls.single.path, ApiEndpoints.paymentsXenditTestSimulate);
      final body = client.calls.single.data as Map;
      expect(body['payment_request_id'], _paymentRequestId);
      expect(body['amount'], 100);
    });
  });

  group('XenditDiagnosticsCard', () {
    late _RecordingDioClient client;

    setUp(() {
      client = _RecordingDioClient();
      // Ang card ay kumukuha ng datasource mula sa GetIt (kapareho ng ibang
      // Head Manager provider) — reset muna para malinis ang registry.
      GetIt.instance.reset();
      GetIt.instance.registerLazySingleton<PaymentRemoteDataSource>(
        () => PaymentRemoteDataSource(client),
      );
      GetIt.instance.registerLazySingleton<DioClient>(() => client);
    });

    tearDown(() => GetIt.instance.reset());

    testWidgets('nagpapakita ng connectivity verdict pagkatapos ng check',
        (tester) async {
      await _pumpCard(tester);
      expect(find.text('Not checked yet.'), findsOneWidget);

      await _tapAndSettle(tester, const ValueKey('xenditCheckConnectivity'));

      expect(find.text('CONNECTED (authenticated)'), findsOneWidget);
      expect(_selectable('yes'), findsOneWidget); // authenticated
      expect(
        find.textContaining('xnd_development_***4f60'),
        findsOneWidget,
        reason: 'masked key preview lang ang ipinapakita',
      );
      expect(find.text('Test API Connectivity'), findsOneWidget);
    });

    testWidgets('test payment ay hiwalay na hakbang at idempotent ang replay',
        (tester) async {
      await _pumpCard(tester);
      // Hindi pa verified → disabled pa ang paggawa ng test payment.
      final createButton = find.byKey(const ValueKey('xenditCreateTestPayment'));
      expect(tester.widget<ElevatedButton>(createButton).onPressed, isNull);

      await _tapAndSettle(tester, const ValueKey('xenditCheckConnectivity'));
      expect(tester.widget<ElevatedButton>(createButton).onPressed, isNotNull);

      await _tapAndSettle(tester, const ValueKey('xenditCreateTestPayment'));
      expect(_selectable(_paymentRequestId), findsOneWidget);
      expect(_selectable('JR-TEST-abc'), findsOneWidget);
      expect(find.textContaining('Checkout URL'), findsOneWidget);
      expect(client.calls.length, 2);
      final firstKey = client.calls.last.headers['x-idempotency-key'];
      expect(firstKey, isNotNull);

      // Replay ng PAREHONG idempotency key → walang bagong test payment.
      await _tapAndSettle(tester, const ValueKey('xenditReplayTestPayment'));
      expect(client.calls.length, 3);
      expect(client.calls.last.headers['x-idempotency-key'], firstKey);
      expect(find.text('Idempotent replay (no new record)'), findsOneWidget);
      // Kapareho pa rin ang payment request id.
      expect(_selectable(_paymentRequestId), findsOneWidget);
    });

    testWidgets('confirmed payment ay galing sa Xendit status', (tester) async {
      await _pumpCard(tester);
      await _tapAndSettle(tester, const ValueKey('xenditCheckConnectivity'));
      await _tapAndSettle(tester, const ValueKey('xenditCreateTestPayment'));

      expect(find.text('No status checked yet.'), findsOneWidget);
      expect(find.text('NOT CONFIRMED'), findsNothing);

      await _tapAndSettle(tester, const ValueKey('xenditRefreshTestStatus'));

      expect(find.text('PAYMENT CONFIRMED'), findsOneWidget);
      expect(find.textContaining('(terminal)'), findsOneWidget);
      expect(client.calls.last.path, ApiEndpoints.paymentsXenditTestStatus);
    });

    testWidgets('sanitized ang error kapag tinanggihan ng Xendit ang key',
        (tester) async {
      client.throwOn = 'diagnostics';
      await _pumpCard(tester);
      await _tapAndSettle(tester, const ValueKey('xenditCheckConnectivity'));

      expect(find.text('Xendit rejected the credentials (401).'), findsOneWidget);
      expect(find.text('CONNECTED (authenticated)'), findsNothing);
    });
  });

  group('Server-side guards (source scan)', () {
    String readFile(String path) =>
        File(path).readAsStringSync().replaceAll('\r\n', '\n');

    test('walang secret key value o env lookup sa Flutter na app', () {
      final offenders = <String>[];
      // Lahat ng Dart file sa `lib/` — hindi kailanman dapat naglalaman ng
      // HALAGA ng Xendit secret key (test o live prefix), ng webhook token,
      // o ng client-side env lookup ng secret na iyon.
      //
      // Ang PANGALAN lang ng env var (`XENDIT_SECRET_KEY`) ay maaaring lumabas
      // sa comment/UI text: ito ay dokumentasyon, hindi credential — ang
      // halaga nito ay hindi kailanman nararating ang client.
      final libFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final file in libFiles) {
        final content = file.readAsStringSync();
        if (content.contains('xnd_development_') ||
            content.contains('xnd_production_') ||
            content.contains('XENDIT_WEBHOOK_TOKEN') ||
            content.contains("env['XENDIT_SECRET_KEY']") ||
            content.contains('env["XENDIT_SECRET_KEY"]') ||
            content.contains('XENDIT_SECRET_KEY=') ||
            RegExp(r'XENDIT_SECRET_KEY\s*:').hasMatch(content)) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'Secret key ay Supabase Edge Function secret LANG');

      // Ang bundled env ng web/mobile build ay hindi rin dapat may secret.
      final env = readFile('assets/env/.env');
      expect(env.contains('XENDIT_SECRET_KEY'), isFalse);
      expect(env.contains('xnd_development_'), isFalse);
      expect(env.contains('xnd_production_'), isFalse);
      // Ang public key (tokenize lang) ang tanging Xendit value doon.
      expect(env.contains('XENDIT_PUBLIC_KEY'), isTrue);
      expect(readFile('assets/env/.env.example').contains('XENDIT_SECRET_KEY'),
          isFalse);
    });

    test('diagnostics actions ay HEAD MANAGER-only at test-key-only', () {
      final src = readFile('supabase/functions/payments-xendit-link/index.ts');
      // Router cases.
      for (final action in [
        'diagnostics',
        'create-test-payment',
        'test-payment-status',
        'simulate-test-payment',
      ]) {
        expect(src.contains("case '$action':"), isTrue, reason: action);
      }
      // Lahat ng diagnostics handler ay dumadaan sa HM gate.
      expect(src.contains('requireRole(authResult, ROLES.HEAD_MANAGER)'), isTrue);
      expect(src.contains('async function handleDiagnostics'), isTrue);
      // Sandbox-only: live key ay tinatanggihan.
      expect(src.contains('isTestSecretKey(secretKey)'), isTrue);
      expect(src.contains('XENDIT_TEST_KEY_REQUIRED'), isTrue);
      // Hindi kailanman nasusulat sa loan/payment record ng test action;
      // `xendit_logs` (may test markers) lang ang naitala.
      final testHandlers = src.substring(
        src.indexOf('async function handleDiagnostics'),
      );
      expect(testHandlers.contains("from('payments')"), isFalse);
      expect(testHandlers.contains("from('loans')"), isFalse);
      expect(testHandlers.contains("from('disbursements')"), isFalse);
      expect(testHandlers.contains("from('xendit_logs')"), isTrue);
      expect(testHandlers.contains('payment_confirmed: false'), isTrue);
      // Idempotency: kailangan ang header at may duplicate lookup.
      expect(src.contains("get('x-idempotency-key')"), isTrue);
      expect(src.contains("eq('payload->>idempotency_key', idempotencyKey)"), isTrue);
      // Ang secret key ay hindi kailanman ibinabalik sa response: ang tanging
      // key-related field ay `key_preview` (naka-mask sa _shared/xendit.ts).
      expect(src.contains('key_preview'), isTrue);
      expect(testHandlers.contains('secret_key'), isFalse);
      expect(testHandlers.contains('maskSecretKey'), isFalse,
          reason: 'ang probe ang nag-mamask; hindi ito ipinapasa sa handler');
      expect(src.contains('keyPreview'), isTrue);
    });

    test('GCash generate ay tumatanggap ng active O overdue na loan', () {
      // REGRESSION: ang `?fn=generate` lang ang humihingi ng strictly 'active'
      // dati, kaya "Loan is not active" ang error ng lender na overdue na —
      // hindi siya makakabayad via GCash kahit iyon ang sandaling kailangan
      // niyang makabayad. Ang office cash (`payments-manage`) at COD
      // (`collections-manage`) ay parehong tumatanggap ng active|overdue.
      final src = readFile('supabase/functions/payments-xendit-link/index.ts');
      expect(src.contains("['active', 'overdue'].includes(loan.status)"), isTrue,
          reason: 'dapat kasama ang overdue sa payable statuses ng GCash');
      expect(src.contains("loan.status !== 'active'"), isFalse,
          reason: 'wala nang strict active-only na check');
      // Hindi kasama ang 'completed' — bayad na iyon.
      expect(src.contains("['active', 'overdue', 'completed'].includes(loan.status)"),
          isFalse);
    });

    test('abuse guard ng GCash ay hindi sumisingil sa invalid na attempt', () {
      // REGRESSION (429 PAYMENT_ATTEMPT_BLOCKED): dating nasa PINAKA-UNANG
      // bahagi ng handler ang `guardRateLimit`, kaya ang bawat 400 — "hindi pa
      // payable" o "bayad na" — ay binibilang bilang attempt at nag-ti-trigger
      // ng 30-minutong block. Ang lender na nag-retry sa sirang status check ay
      // naka-429 nang wala namang na-generate na invoice ni isang link.
      // Ngayon: aktibong block lang ang tinitignan sa umpisa (walang bagong
      // attempt), at ang pagbilang ay katabi na ng tunay na invoice generation.
      final src = readFile('supabase/functions/payments-xendit-link/index.ts');
      final statusCheck =
          src.indexOf("['active', 'overdue'].includes(loan.status)");
      final paidCheck =
          src.indexOf("return errorResponse('Installment already paid'");
      final guard = src.indexOf('guardRateLimit({');
      final earlyBlock = src.indexOf('const activeBlock = await checkBlock(attemptKey);');
      expect(statusCheck, greaterThan(-1));
      expect(paidCheck, greaterThan(-1));
      expect(earlyBlock, greaterThan(-1),
          reason: 'dapat may murang block check sa umpisa, bago ang validation');
      expect(earlyBlock, lessThan(statusCheck));
      expect(guard, greaterThan(statusCheck),
          reason: 'ang pagbilang ay dapat pagkatapos ng payable-status check');
      expect(guard, greaterThan(paidCheck),
          reason: 'hindi dapat magbilang ang "already paid" na pagtanggi');
      // Isang mensahe lang ang pinagmulan ng 429 at may kasamang next step.
      expect(src.contains('function paymentAttemptBlockedResponse'), isTrue);
      expect(src.contains('or pay via Cash on Delivery in the meantime'), isTrue);
      // Malinaw na 503/502 sa halip na generic 500 ("Internal server error").
      expect(src.contains("'XENDIT_NOT_CONFIGURED'"), isTrue);
      expect(src.contains("'XENDIT_INVOICE_FAILED'"), isTrue);
    });

    test('tunay pa rin ang webhook token verification ng payment webhook', () {
      final src = readFile('supabase/functions/payments-xendit-webhook/index.ts');
      expect(src.contains('verifyWebhookToken(req)'), isTrue);
      expect(src.contains("status === 'verified'"), isTrue,
          reason: 'duplicate webhook processing ay hinaharangan');
      expect(src.contains('AMOUNT_MISMATCH'), isTrue);
    });

    test('ang Xendit helper ay may read-only probe at test-key guards', () {
      final src = readFile('supabase/functions/_shared/xendit.ts');
      expect(src.contains("'/v3/payment_requests'"), isTrue);
      expect(src.contains('XENDIT_PROBE_PAYMENT_REQUEST_ID'), isTrue);
      // Ang probe ay GET lang — hindi kailanman nag-po-POST ng payment.
      expect(src.contains('export async function probeXenditConnectivity'), isTrue);
      expect(src.contains("xenditRequest(path, { method: 'GET', secretKey })"), isTrue);
      // Timeout sa bawat call (hindi nag-hahang ang Edge Function).
      expect(src.contains('AbortSignal.timeout'), isTrue);
      // Hindi kailanman bumabalik ang buong key, at hindi kasama sa messages.
      expect(src.contains('maskSecretKey'), isTrue);
      expect(src.contains('XENDIT_API_VERSION'), isTrue);
      expect(src.contains("'2024-11-11'"), isTrue);
    });

    test('migration 00183 ay partial unique index lang (walang schema change)',
        () {
      final mig = readFile(
          'supabase/migrations/00183_xendit_test_payment_idempotency.sql');
      expect(mig.contains('CREATE UNIQUE INDEX IF NOT EXISTS'), isTrue);
      expect(mig.contains("payload ->> 'idempotency_key'"), isTrue);
      expect(mig.contains("status = 'test_created'"), isTrue);
      // Walang ALTER TABLE / DROP / policy change sa existing data.
      expect(mig.contains('ALTER TABLE'), isFalse);
      expect(mig.contains('DROP '), isFalse);
      expect(mig.contains('DELETE FROM'), isFalse);
    });
  });
}
