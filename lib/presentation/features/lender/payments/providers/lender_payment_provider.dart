// lib/presentation/features/lender/payments/providers/lender_payment_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
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

  /// Requests a rider to collect the installment at the lender's home.
  Future<bool> requestRiderCollection({required String loanScheduleId}) async {
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await _collectionDs.requestRiderCollection(
          loanScheduleId: loanScheduleId, type: 'rider');
      state = state.copyWith(isSubmitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
      return false;
    }
  }

  /// Requests an office visit so the lender can pay the installment in person.
  Future<bool> requestOfficePayment({required String loanScheduleId}) async {
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await _collectionDs.requestRiderCollection(
          loanScheduleId: loanScheduleId, type: 'office');
      state = state.copyWith(isSubmitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(
          isSubmitting: false, error: ErrorHandler.handle(e).message);
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
