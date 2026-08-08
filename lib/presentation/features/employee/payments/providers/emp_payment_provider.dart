// lib/presentation/features/employee/payments/providers/emp_payment_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/payment_remote_datasource.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

final empPaymentListProvider =
    StateNotifierProvider<EmpPaymentNotifier, AsyncValue<Map<String, dynamic>>>(
        (ref) {
  return EmpPaymentNotifier(sl<PaymentRemoteDataSource>());
});

class EmpPaymentNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>>>
    with RealtimeRefreshMixin {
  final PaymentRemoteDataSource _ds;
  EmpPaymentNotifier(this._ds)
      : super(const AsyncData({'items': [], 'total': 0})) {
    bindRealtimeRefresh(['payments'], refresh: loadList);
    loadList();
  }

  Future<void> loadList({String? method, String? status, int page = 1}) async {
    state = const AsyncLoading();
    try {
      final data =
          await _ds.getList(method: method, status: status, page: page);
      state = AsyncData(data);
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }

  Future<bool> recordOfficePayment(
      {required String loanId,
      required String loanScheduleId,
      required double amount,
      String? notes,
      required String idempotencyKey}) async {
    try {
      await _ds.recordOffice(
          loanId: loanId,
          loanScheduleId: loanScheduleId,
          amount: amount,
          notes: notes,
          idempotencyKey: idempotencyKey);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getDetail(String paymentId) async {
    try {
      final p = await _ds.getPaymentDetail(paymentId);
      return {
        'id': p.id,
        'loan_number': p.loanNumber,
        'lender_name': p.lenderName,
        'status': p.status,
        'amount': p.amount,
        'payment_method': p.method,
        'reference_number': p.referenceNumber ?? '',
        'xendit_payment_id': p.xenditPaymentId ?? '',
        'recorded_by_name': p.recordedByName,
        'created_at': p.createdAt.toIso8601String(),
        'notes': p.notes ?? '',
      };
    } catch (e) {
      return null;
    }
  }
}
