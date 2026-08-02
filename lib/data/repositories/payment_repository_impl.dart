// lib/data/repositories/payment_repository_impl.dart
import '../../domain/repositories/i_payment_repository.dart';
import '../datasources/remote/payment_remote_datasource.dart';

class PaymentRepositoryImpl implements IPaymentRepository {
  final PaymentRemoteDataSource _ds;
  PaymentRepositoryImpl(this._ds);

  @override
  Future<void> recordOfficePayment(Map<String, dynamic> data) =>
      _ds.recordOfficePayment(
        loanId: (data['loanId'] ?? data['loan_id'] ?? '').toString(),
        loanScheduleId:
            (data['loanScheduleId'] ?? data['loan_schedule_id'] ?? '')
                .toString(),
        amount: (data['amount'] ?? 0).toDouble(),
        notes: (data['notes'] as String?) ?? data['notes']?.toString(),
        idempotencyKey:
            (data['idempotencyKey'] ?? data['idempotency_key'] ?? '').toString(),
      );

  @override
  Future<Map<String, dynamic>> generateXenditLink(Map<String, dynamic> data) =>
      _ds.generateXenditLink(
        loanId: (data['loanId'] ?? data['loan_id'] ?? '').toString(),
        loanScheduleId:
            (data['loanScheduleId'] ?? data['loan_schedule_id'] ?? '')
                .toString(),
      );

  @override
  Future<void> reversePayment(String paymentId, String reason) =>
      _ds.reversePayment(paymentId: paymentId, reason: reason);

  @override
  Future<String?> getReceiptUrl(String paymentId) =>
      _ds.getReceipt(paymentId: paymentId);

  @override
  Future<List<dynamic>> getPaymentList(
          {String? status, String? method, int page = 1}) =>
      _ds.getPaymentList(status: status, method: method, page: page);
}
