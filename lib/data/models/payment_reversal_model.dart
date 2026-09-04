// lib/data/models/payment_reversal_model.dart
import '../../core/utils/timezone.dart';

class PaymentReversalModel {
  final String id;
  final String paymentId;
  final String reversedById;
  final String? reversedByName;
  final String reason;
  final DateTime createdAt;

  const PaymentReversalModel({
    required this.id,
    required this.paymentId,
    required this.reversedById,
    this.reversedByName,
    required this.reason,
    required this.createdAt,
  });

  factory PaymentReversalModel.fromJson(Map<String, dynamic> json) =>
      PaymentReversalModel(
        id: json['id'] ?? '',
        paymentId: json['payment_id'] ?? '',
        reversedById: json['reversed_by'] ?? '',
        reversedByName: json['reverser'] != null
            ? '${json['reverser']['first_name']} ${json['reverser']['last_name']}'
            : null,
        reason: json['reason'] ?? '',
        createdAt: json['created_at'] != null
            ? parseManila(json['created_at'])!
            : DateTime.now(),
      );
}
