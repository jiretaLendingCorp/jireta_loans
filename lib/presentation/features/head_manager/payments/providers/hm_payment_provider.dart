// lib/presentation/features/head_manager/payments/providers/hm_payment_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/payment_remote_datasource.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

final hmPaymentProvider = AutoDisposeStateNotifierProvider<HmPaymentNotifier,
    AsyncValue<Map<String, dynamic>>>((ref) {
  return HmPaymentNotifier(sl<PaymentRemoteDataSource>());
});

class HmPaymentNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>>>
    with RealtimeRefreshMixin {
  final PaymentRemoteDataSource _ds;
  HmPaymentNotifier(this._ds)
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

  Future<bool> reverse(
      {required String paymentId, required String reason}) async {
    try {
      await _ds.reverse(paymentId: paymentId, reason: reason);
      await loadList();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<String?> getReceipt(String paymentId) async {
    try {
      return await _ds.getReceipt(paymentId: paymentId);
    } catch (e) {
      return null;
    }
  }

  Future<bool> reversePayment({
    required String paymentId,
    required String reason,
  }) =>
      reverse(paymentId: paymentId, reason: reason);
}
