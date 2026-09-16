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
  final int totalCount;

  /// Uri ng payment na naka-select (all · gcash · office_cash ·
  /// rider_collection).
  final String methodFilter;
  final String search;
  final String? dateFrom;
  final String? dateTo;

  const EmpPaymentState({
    this.payments = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalCount = 0,
    this.methodFilter = 'all',
    this.search = '',
    this.dateFrom,
    this.dateTo,
  });

  EmpPaymentState copyWith({
    List<Map<String, dynamic>>? payments,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    String? methodFilter,
    String? search,
    String? dateFrom,
    String? dateTo,
  }) =>
      EmpPaymentState(
          payments: payments ?? this.payments,
          isLoading: isLoading ?? this.isLoading,
          error: error,
          currentPage: currentPage ?? this.currentPage,
          totalPages: totalPages ?? this.totalPages,
          totalCount: totalCount ?? this.totalCount,
          methodFilter: methodFilter ?? this.methodFilter,
          search: search ?? this.search,
          dateFrom: dateFrom ?? this.dateFrom,
          dateTo: dateTo ?? this.dateTo);

  /// Kopya na may bagong date range — hindi `copyWith` dahil pinapanatili
  /// nito ang lumang value kapag `null` (kailangang mai-clear ang filter).
  EmpPaymentState withDateRange(String? from, String? to) => EmpPaymentState(
        payments: payments,
        isLoading: isLoading,
        error: error,
        currentPage: currentPage,
        totalPages: totalPages,
        totalCount: totalCount,
        methodFilter: methodFilter,
        search: search,
        dateFrom: from,
        dateTo: to,
      );
}

class EmpPaymentNotifier extends StateNotifier<EmpPaymentState>
    with RealtimeRefreshMixin<EmpPaymentState> {
  final PaymentRemoteDataSource _ds;
  EmpPaymentNotifier(this._ds) : super(const EmpPaymentState()) {
    bindRealtimeRefresh(['payments'], refresh: () => fetch(silent: true));
    fetch();
  }

  Future<void> fetch({int page = 1, bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _ds.getPaymentListPage(
        page: page,
        method: state.methodFilter == 'all' ? null : state.methodFilter,
        search: state.search.isEmpty ? null : state.search,
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
      );
      final payments =
          (res['data'] as List? ?? []).cast<Map<String, dynamic>>();
      final meta = res['meta'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
          payments: payments,
          isLoading: false,
          currentPage: meta['page'] as int? ?? 1,
          totalPages: meta['total_pages'] as int? ?? 1,
          totalCount: (meta['total'] as num?)?.toInt() ?? payments.length);
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  /// Uri ng payment at/o search — ISANG fetch lang kapag sabay na nagbago
  /// (hal. nag-search bago lumipat ng uri ng payment).
  void setFilters({String? method, String? search}) {
    state = state.copyWith(
      methodFilter: method ?? state.methodFilter,
      search: search ?? state.search,
    );
    fetch();
  }

  void setDateRange(String? from, String? to) {
    state = state.withDateRange(from, to);
    fetch();
  }

  // Legacy alias for older callers
  Future<void> loadList(
      {String? method, int page = 1, bool silent = false}) async {
    if (method != null) state = state.copyWith(methodFilter: method);
    await fetch(page: page, silent: silent);
  }

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
