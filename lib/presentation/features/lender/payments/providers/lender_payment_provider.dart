// lib/presentation/features/lender/payments/providers/lender_payment_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/errors/failure.dart';
import '../../../../../core/utils/logger.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/payment_remote_datasource.dart';
import '../../../../../data/datasources/remote/collection_remote_datasource.dart';
import '../../../../../data/models/payment_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class LenderPaymentState {
  final List<PaymentModel> payments;
  final bool isLoading;
  final String? error;
  final bool isSubmitting;
  final String? xenditUrl;

  const LenderPaymentState({
    this.payments = const [],
    this.isLoading = false,
    this.error,
    this.isSubmitting = false,
    this.xenditUrl,
  });

  LenderPaymentState copyWith({
    List<PaymentModel>? payments,
    bool? isLoading,
    String? error,
    bool? isSubmitting,
    String? xenditUrl,
  }) =>
      LenderPaymentState(
        payments: payments ?? this.payments,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        xenditUrl: xenditUrl ?? this.xenditUrl,
      );
}

class LenderPaymentNotifier extends StateNotifier<LenderPaymentState>
    with RealtimeRefreshMixin {
  final PaymentRemoteDataSource _ds;
  final CollectionRemoteDataSource _collectionDs;

  LenderPaymentNotifier(this._ds, this._collectionDs)
      : super(const LenderPaymentState()) {
    bindRealtimeRefresh(['payments', 'loan_schedules'],
        refresh: () => loadPayments(silent: true));
    loadPayments();
  }

  Future<void> loadPayments({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final payments = await _ds.getPaymentList(page: 1);
      state = state.copyWith(payments: payments, isLoading: false);
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  Future<String?> generateGcashLink({
    required String loanId,
    required String loanScheduleId,
  }) async {
    state = state.copyWith(isSubmitting: true);
    try {
      final result = await _ds.generateXenditLink(
        loanId: loanId,
        loanScheduleId: loanScheduleId,
      );
      final url = result['xendit_invoice_url'] as String?;
      state = state.copyWith(isSubmitting: false, xenditUrl: url);
      return url;
    } catch (e) {
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
      return null;
    }
  }

  Future<String?> getReceipt(String paymentId) async {
    try {
      return await _ds.getReceipt(paymentId: paymentId);
    } catch (_) {
      return null;
    }
  }

  static const _pendingMessage = 'You have already pending payment';

  /// Maps raw backend/Dio failures to user-facing messages.
  /// Keeps backend's own message for most cases, but translates
  /// a few known server sentences into friendlier explanations
  /// so the lender sees WHY the request was rejected instead of
  /// a generic "Request Not Sent".
  String _mapError(Failure failure) {
    final raw = failure.message;
    final code = failure.code ?? '';
    final low = raw.toLowerCase();

    // 1) Already-pending / conflict — always show the pending dialog.
    if (code == 'ALREADY_IN_PROGRESS' ||
        (code == 'CONFLICT' && low.contains('already pending')) ||
        low.contains('already pending') ||
        low.contains('already in progress') ||
        low.contains('collection is already')) {
      return _pendingMessage;
    }

    // 2) Loan not payable yet (common when loan is still 'pending',
    // 'approved' or 'under_review' and not yet disbursed).
    if (low.contains('not in a payable status') || code == 'INVALID_STATUS') {
      return 'Your loan is not yet ready for payment collection. Only Active or Overdue loans can be collected. If your loan was just approved, please wait for fund release/disbursement. Contact the office if you think this is an error.';
    }

    // 3) Schedule already paid.
    if (low.contains('already paid')) {
      return 'This installment is already fully paid.';
    }

    // 4) Schedule not found / wrong ID (often stale schedule cache).
    if (low.contains('schedule not found') || (code == 'NOT_FOUND' && low.contains('schedule'))) {
      return 'Installment not found. Please pull to refresh your Payment Schedule and try again. (schedule_id: $low)';
    }

    // 5) Missing schedule ID — client bug, surface clearly.
    if (low.contains('loan_schedule_id is required')) {
      return 'Missing installment information. Please go back to the Payment Schedule and tap Pay again.';
    }

    // 6) Auth / session.
    if (code == 'UNAUTHORIZED' || low.contains('invalid or expired token') || low.contains('missing or invalid authorization')) {
      return 'Your session has expired. Please log out and log in again.';
    }
    if (code == 'FORBIDDEN' || code == 'ACCOUNT_ARCHIVED' || low.contains('access denied') || low.contains('required role')) {
      return 'Access denied. Please make sure you are logged in as a lender.';
    }
    if (code == 'ACCOUNT_PENDING') {
      return 'Your account is pending approval. Please contact the office.';
    }

    // 7) Network / server reachability — keep the interceptor's friendly text.
    if (failure is NetworkFailure) return raw;

    // 8) Generic fallbacks so the UI never shows a bare "An error occurred"
    //    without context. Preserve the raw text for debugging.
    if (low == 'an error occurred' || low == 'an error occurred.') {
      return 'Server error while creating your request. Please try again in a moment. (code: ${code.isNotEmpty ? code : 'unknown'})';
    }

    // 9) Everything else — surface the backend's own sentence. This is the
    //    "proper error" the user asked to debug: e.g. Rider not available,
    //    validation, etc. Keeping it verbatim ensures new backend messages
    //    are immediately visible without an app update.
    return raw;
  }

  /// Requests a rider to collect the installment at the lender's home.
  Future<bool> requestRiderCollection({required String loanScheduleId}) async {
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      AppLogger.d('[LenderPayment] requestRiderCollection schedule=$loanScheduleId');
      final res = await _collectionDs.requestRiderCollection(
          loanScheduleId: loanScheduleId, type: 'rider');
      final msg = (res['message'] as String? ?? '').toLowerCase();
      if (msg.contains('already pending')) {
        AppLogger.w('[LenderPayment] rider request idempotent pending: $res');
        state = state.copyWith(
            isSubmitting: false, error: _pendingMessage);
        return false;
      }
      AppLogger.i('[LenderPayment] rider request success: $res');
      state = state.copyWith(isSubmitting: false);
      return true;
    } catch (e, st) {
      final failure = ErrorHandler.handle(e);
      AppLogger.e('[LenderPayment] requestRiderCollection FAILED code=${failure.code} msg=${failure.message} schedule=$loanScheduleId', e, st);
      if (kDebugMode) debugPrint('[LenderPayment] Raw exception: $e');
      final mapped = _mapError(failure);
      state = state.copyWith(
          isSubmitting: false, error: mapped);
      return false;
    }
  }

  /// Requests an office visit so the lender can pay the installment in person.
  Future<bool> requestOfficePayment({required String loanScheduleId}) async {
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      AppLogger.d('[LenderPayment] requestOfficePayment schedule=$loanScheduleId');
      final res = await _collectionDs.requestRiderCollection(
          loanScheduleId: loanScheduleId, type: 'office');
      final msg = (res['message'] as String? ?? '').toLowerCase();
      if (msg.contains('already pending')) {
        AppLogger.w('[LenderPayment] office request idempotent pending: $res');
        state = state.copyWith(
            isSubmitting: false, error: _pendingMessage);
        return false;
      }
      AppLogger.i('[LenderPayment] office request success: $res');
      state = state.copyWith(isSubmitting: false);
      return true;
    } catch (e, st) {
      final failure = ErrorHandler.handle(e);
      AppLogger.e('[LenderPayment] requestOfficePayment FAILED code=${failure.code} msg=${failure.message} schedule=$loanScheduleId', e, st);
      if (kDebugMode) debugPrint('[LenderPayment] Raw exception: $e');
      final mapped = _mapError(failure);
      state = state.copyWith(
          isSubmitting: false, error: mapped);
      return false;
    }
  }

  Future<void> loadPaymentHistory() => loadPayments();

  Future<Map<String, dynamic>> getReceiptData(String paymentId) async {
    try {
      final p = await _ds.getPaymentDetail(paymentId);
      return {
        'receipt_url': p.receiptUrl,
        'amount': p.amount,
        'payment_method': p.method,
        'status': p.status,
        'reference_number': p.referenceNumber ?? '',
        'created_at': p.createdAt.toIso8601String(),
        'loan_number': p.loanNumber,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> refresh() => loadPayments();
}

final lenderPaymentProvider =
    AutoDisposeStateNotifierProvider<LenderPaymentNotifier, LenderPaymentState>(
        (ref) {
  return LenderPaymentNotifier(
    sl<PaymentRemoteDataSource>(),
    sl<CollectionRemoteDataSource>(),
  );
});
