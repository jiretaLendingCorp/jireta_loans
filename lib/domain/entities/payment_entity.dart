// lib/domain/entities/payment_entity.dart
class PaymentEntity {
  final String id;
  final String loanId;
  final String? loanScheduleId;
  final double amount;
  final String paymentMethod;
  final String status;
  final String? xenditPaymentId;
  final String? referenceNumber;
  final String? recordedBy;
  final String? idempotencyKey;
  final DateTime? paidAt;
  final DateTime createdAt;

  const PaymentEntity({
    required this.id,
    required this.loanId,
    this.loanScheduleId,
    required this.amount,
    required this.paymentMethod,
    required this.status,
    this.xenditPaymentId,
    this.referenceNumber,
    this.recordedBy,
    this.idempotencyKey,
    this.paidAt,
    required this.createdAt,
  });
}
