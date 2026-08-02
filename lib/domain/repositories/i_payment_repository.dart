// lib/domain/repositories/i_payment_repository.dart
abstract class IPaymentRepository {
  Future<void> recordOfficePayment(Map<String, dynamic> data);
  Future<Map<String, dynamic>> generateXenditLink(Map<String, dynamic> data);
  Future<void> reversePayment(String paymentId, String reason);
  Future<String?> getReceiptUrl(String paymentId);
  Future<List<dynamic>> getPaymentList({String? status, int page});
}
