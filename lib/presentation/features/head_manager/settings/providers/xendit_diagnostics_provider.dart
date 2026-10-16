// lib/presentation/features/head_manager/settings/providers/xendit_diagnostics_provider.dart
//
// State para sa XENDIT SANDBOX DIAGNOSTICS card (Head Manager Settings).
//
// Layunin: (1) mapatunayang gumagana ang `XENDIT_SECRET_KEY`, (2) makagawa ng
// TEST payment request (sandbox) nang HIWALAY, at (3) matingnan ang
// Xendit-confirmed status nito.
//
// Mahalaga: WALANG secret key sa client — nasa Supabase Edge Function secret
// store lang ito at hindi kailanman bumabalik sa Flutter. Wala rin itong
// ginagalaw na loan o payment record; test-only ito (`xendit_logs` lang ang
// naitala, at may test markers).
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/errors/app_exception.dart';
import '../../../../../core/utils/helpers.dart';
import '../../../../../data/datasources/remote/payment_remote_datasource.dart';

/// Channel codes na sinusuportahan ng sandbox test payment request (PH e-wallets).
const List<String> xenditTestChannels = ['GCASH', 'MAYA', 'GRABPAY', 'SHOPEEPAY'];

/// Default na halaga ng test payment — ilang piso lang, kitang-kita na test.
const double xenditTestDefaultAmount = 100;

class XenditDiagnosticsState {
  /// May tumatakbo pang request (disable ang UI buttons).
  final bool busy;

  /// Sanitized na sagot ng `?fn=diagnostics` (status/authenticated/message).
  final Map<String, dynamic>? connectivity;

  /// Test payment request na nagawa na (`payment_request_id`, `reference_id`).
  final Map<String, dynamic>? testPayment;

  /// Xendit-confirmed status ng test payment request.
  final Map<String, dynamic>? testStatus;

  /// Sanitized na error message (galing sa Edge Function / Dio interceptor).
  final String? errorMessage;

  /// Impormasyon/success message (hal. "duplicate request — same key").
  final String? infoMessage;

  /// Ang huling ginamit na idempotency key — ipinapakita para malinaw na
  /// kaparehong test transaction ang sinusubukan kapag nag-replay.
  final String? lastIdempotencyKey;

  /// Halaga ng test payment (PHP).
  final double amount;

  /// Channel code ng test payment.
  final String channelCode;

  const XenditDiagnosticsState({
    this.busy = false,
    this.connectivity,
    this.testPayment,
    this.testStatus,
    this.errorMessage,
    this.infoMessage,
    this.lastIdempotencyKey,
    this.amount = xenditTestDefaultAmount,
    this.channelCode = 'GCASH',
  });

  /// `connected` lang kapag ang aktwal na sagot ng Xendit ang nagpapatunay.
  bool get isConnected => connectivity?['status'] == 'connected';

  /// Puwede na bang gumawa ng sandbox test payment (naka-test key + verified).
  bool get sandboxTestReady => connectivity?['sandbox_test_ready'] == true;

  /// Ang key ay LIVE (production) — hindi dapat gamitin sa test paths.
  bool get isLiveKey => connectivity?['environment'] == 'live';

  String? get paymentRequestId =>
      (testPayment?['payment_request_id'] ?? testStatus?['payment_request_id'])
          as String?;

  /// True kapag kumpirmado na ng Xendit (o validated webhook) ang bayad.
  bool get paymentConfirmed => testStatus?['payment_confirmed'] == true;

  bool get testStatusTerminal => testStatus?['terminal'] == true;

  /// Ang huling test payment ay idempotent replay (hindi bagong record).
  bool get isDuplicateRequest => testPayment?['duplicate'] == true;

  XenditDiagnosticsState copyWith({
    bool? busy,
    Map<String, dynamic>? connectivity,
    Map<String, dynamic>? testPayment,
    Map<String, dynamic>? testStatus,
    String? errorMessage,
    String? infoMessage,
    String? lastIdempotencyKey,
    double? amount,
    String? channelCode,
    bool clearError = false,
    bool clearInfo = false,
    bool clearTestStatus = false,
  }) {
    return XenditDiagnosticsState(
      busy: busy ?? this.busy,
      connectivity: connectivity ?? this.connectivity,
      testPayment: testPayment ?? this.testPayment,
      testStatus: clearTestStatus ? null : (testStatus ?? this.testStatus),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      infoMessage: clearInfo ? null : (infoMessage ?? this.infoMessage),
      lastIdempotencyKey: lastIdempotencyKey ?? this.lastIdempotencyKey,
      amount: amount ?? this.amount,
      channelCode: channelCode ?? this.channelCode,
    );
  }
}

class XenditDiagnosticsNotifier extends StateNotifier<XenditDiagnosticsState> {
  XenditDiagnosticsNotifier() : super(const XenditDiagnosticsState());

  /// Ang datasource ay kino-resolve LANG kapag pinindot ang isang action — ang
  /// card ay basta-basta nagre-render sa Settings screen kahit hindi pa tapos
  /// ang DI setup (hal. sa widget test ng screen, o sa panahon ng app boot),
  /// at ang anumang DI/router error ay lumalabas bilang sanitized na mensahe
  /// sa loob ng card imbes na mag-crash ang buong screen.
  PaymentRemoteDataSource get _ds => sl<PaymentRemoteDataSource>();

  void setAmount(double value) {
    if (value.isNaN || value < 0) return;
    state = state.copyWith(amount: value, clearError: true);
  }

  void setChannelCode(String code) {
    state = state.copyWith(channelCode: code, clearError: true, clearInfo: true);
  }

  /// `?fn=diagnostics` — read-only na pag-verify ng test secret key.
  Future<void> checkConnectivity() async {
    state = state.copyWith(
      busy: true,
      clearError: true,
      clearInfo: true,
      clearTestStatus: true,
    );
    try {
      final data = await _ds.checkXenditConnectivity();
      final status = (data['status'] ?? 'unverified').toString();
      state = state.copyWith(
        busy: false,
        connectivity: data,
        infoMessage: _probeInfo(data, status),
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        busy: false,
        errorMessage: _messageOf(e),
        clearInfo: true,
      );
    }
  }

  /// `?fn=create-test-payment` — bagong sandbox payment request.
  ///
  /// [reuseKey] = `true` kapag sinasadya nating i-replay ang PAREHONG
  /// idempotency key para ipakita ang duplicate-request protection (kaparehong
  /// `payment_request_id`, walang bagong Xendit call).
  Future<void> createTestPayment({bool reuseKey = false}) async {
    final amount = state.amount <= 0 ? xenditTestDefaultAmount : state.amount;
    final key = (reuseKey && state.lastIdempotencyKey != null)
        ? state.lastIdempotencyKey!
        : AppHelpers.generateIdempotencyKey();

    state = state.copyWith(
      busy: true,
      lastIdempotencyKey: key,
      clearError: true,
      clearInfo: true,
      clearTestStatus: true,
    );
    try {
      final data = await _ds.createXenditTestPayment(
        amount: amount,
        idempotencyKey: key,
        channelCode: state.channelCode,
      );
      final duplicate = data['duplicate'] == true;
      state = state.copyWith(
        busy: false,
        testPayment: data,
        infoMessage: duplicate
            ? 'Idempotent replay — kaparehong payment request ang ibinalik, walang bagong test payment na nagawa.'
            : 'Sandbox test payment request created. Loan at payment records ay HINDI ginagalaw.',
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        busy: false,
        errorMessage: _messageOf(e),
        clearInfo: true,
      );
    }
  }

  /// `?fn=test-payment-status` — Xendit-confirmed status (read-only).
  Future<void> refreshTestPaymentStatus() async {
    final id = state.paymentRequestId;
    if (id == null || id.isEmpty) {
      state = state.copyWith(
        errorMessage: 'Create a sandbox test payment request first.',
        clearInfo: true,
      );
      return;
    }
    state = state.copyWith(busy: true, clearError: true, clearInfo: true);
    try {
      final data = await _ds.getXenditTestPaymentStatus(paymentRequestId: id);
      final status = (data['status'] ?? 'unknown').toString();
      state = state.copyWith(
        busy: false,
        testStatus: data,
        infoMessage: data['payment_confirmed'] == true
            ? 'Xendit confirmed the test payment (status: $status).'
            : 'Xendit status: $status. Hindi pa kumpirmadong bayad.',
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        busy: false,
        errorMessage: _messageOf(e),
        clearInfo: true,
      );
    }
  }

  /// `?fn=simulate-test-payment` — documented TEST-MODE-ONLY na pag-complete.
  Future<void> simulateTestPayment() async {
    final id = state.paymentRequestId;
    if (id == null || id.isEmpty) {
      state = state.copyWith(
        errorMessage: 'Create a sandbox test payment request first.',
        clearInfo: true,
      );
      return;
    }
    state = state.copyWith(busy: true, clearError: true, clearInfo: true);
    try {
      final data = await _ds.simulateXenditTestPayment(
        paymentRequestId: id,
        amount: state.amount > 0 ? state.amount : null,
      );
      state = state.copyWith(
        busy: false,
        infoMessage:
            'Simulation accepted (status: ${data['status'] ?? 'PENDING'}). I-refresh ang status para sa Xendit-confirmed resulta.',
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        busy: false,
        errorMessage: _messageOf(e),
        clearInfo: true,
      );
    }
  }

  /// Rason/explanasyon na ipinapakita sa tabi ng hatol ng connectivity check.
  String _probeInfo(Map<String, dynamic> data, String status) {
    final message = (data['message'] ?? '').toString();
    final warning = (data['warning'] ?? '').toString();
    if (warning.isNotEmpty) return '$message $warning';
    return message.isEmpty ? 'Status: $status' : message;
  }

  /// Sanitized na error message. Ang Dio interceptor ay naglalagay na ng
  /// friendly message (mula sa `error.message` ng Edge Function) sa
  /// `DioException.message`, kaya hindi na natin ipinapakita ang raw error.
  String _messageOf(Object e) {
    if (e is DioException) {
      final inner = e.error;
      if (inner is AppException && inner.message.trim().isNotEmpty) {
        return inner.message.trim();
      }
      final message = e.message?.trim() ?? '';
      if (message.isNotEmpty) return message;
      return 'Request failed. Please check your connection and try again.';
    }
    if (e is AppException) return e.message;
    return 'Request failed. Please check your connection and try again.';
  }
}

final xenditDiagnosticsProvider = AutoDisposeStateNotifierProvider<
    XenditDiagnosticsNotifier, XenditDiagnosticsState>(
  (ref) => XenditDiagnosticsNotifier(),
);
