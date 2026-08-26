// lib/presentation/features/employee/payments/providers/emp_payment_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/payment_remote_datasource.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class EmpPaymentState {
  final List<Map<String, dynamic>> payments;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalPages;
  const EmpPaymentState(
      {this.payments = const [],
      this.isLoading = false,
      this.error,
      this.currentPage = 1,
      this.totalPages = 1});
  EmpPaymentState copyWith(
          {List<Map<String, dynamic>>? payments,
          bool? isLoading,
          String? error,
          int? currentPage,
          int? totalPages}) =>
      EmpPaymentState(
          payments: payments ?? this.payments,
          isLoading: isLoading ?? this.isLoading,
          error: error,
          currentPage: currentPage ?? this.currentPage,
          totalPages: totalPages ?? this.totalPages);
}

class EmpPaymentNotifier extends StateNotifier<EmpPaymentState>
    with RealtimeRefreshMixin<EmpPaymentState> {
  final PaymentRemoteDataSource _ds;
  EmpPaymentNotifier(this._ds) : super(const EmpPaymentState()) {
    bindRealtimeRefresh(['payments'], refresh: () => fetch(silent: true));
    fetch();
  }

  Future<void> fetch(
      {int page = 1, String? method, String? status, bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _ds.getPaymentListPage(
          page: page, method: method, status: status);
      final payments =
          (res['data'] as List? ?? []).cast<Map<String, dynamic>>();
      final meta = res['meta'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
          payments: payments,
          isLoading: false,
          currentPage: meta['page'] as int? ?? 1,
          totalPages: meta['total_pages'] as int? ?? 1);
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  // Legacy alias for older callers
  Future<void> loadList(
      {String? method, String? status, int page = 1, bool silent = false}) =>
      fetch(page: page, method: method, status: status, silent: silent);

  Future<bool> reversePayment(String paymentId) async {
    try {
      await _ds.reversePayment(
          paymentId: paymentId, reason: 'Reversed by Employee');
      await fetch();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> reverse(
          {required String paymentId, required String reason}) async =>
      reversePayment(paymentId);

  Future<String?> getReceipt(String paymentId) async {
    try {
      return await _ds.getReceipt(paymentId: paymentId);
    } catch (e) {
      return null;
    }
  }

  Future<bool> recordOfficePayment(
      {required String loanId,
      required String loanScheduleId,
      required double amount,
      String? notes,
      String? assignmentId,
      required String idempotencyKey}) async {
    try {
      await _ds.recordOffice(
          loanId: loanId,
          loanScheduleId: loanScheduleId,
          amount: amount,
          notes: notes,
          assignmentId: assignmentId,
          idempotencyKey: idempotencyKey);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> recordOffice(
          {required String loanId,
          required String loanScheduleId,
          required double amount,
          String? notes,
          String? assignmentId,
          required String idempotencyKey}) =>
      recordOfficePayment(
          loanId: loanId,
          loanScheduleId: loanScheduleId,
          amount: amount,
          notes: notes,
          assignmentId: assignmentId,
          idempotencyKey: idempotencyKey);

  Future<Map<String, dynamic>?> getDetail(String paymentId) async {
    try {
      final p = await _ds.getPaymentDetail(paymentId);
      final xenditId = p.xenditPaymentId?.trim() ?? '';
      final refNumber = p.referenceNumber?.trim() ?? '';
      return {
        'id': p.id,
        'loan_number': p.loanNumber,
        'lender_name': p.lenderName,
        'status': p.status,
        'amount': p.amount,
        'payment_method': p.method,
        'method': p.method,
        'reference_number': refNumber.isEmpty ? null : refNumber,
        'xendit_payment_id':
            p.method == 'gcash' && xenditId.isNotEmpty ? xenditId : null,
        'recorded_by_name': p.recordedByName,
        'recorded_by_user': p.recordedByUser,
        'loan': p.loan,
        'created_at': p.createdAt.toIso8601String(),
        'notes': p.notes ?? '',
      };
    } catch (e) {
      return null;
    }
  }
}

final empPaymentListProvider =
    AutoDisposeStateNotifierProvider<EmpPaymentNotifier, EmpPaymentState>((ref) {
  return EmpPaymentNotifier(sl<PaymentRemoteDataSource>());
});

// Alias for HM-style naming if needed
final empPaymentProvider = empPaymentListProvider;
