// lib/data/models/xendit_log_model.dart
import '../../core/utils/timezone.dart';

class XenditLogModel {
  final String id;
  final String? loanId;
  final String? paymentId;
  final String? disbursementId;
  final String type;
  final String xenditReferenceId;
  final String status;
  final double amount;
  final Map<String, dynamic>? requestPayload;
  final Map<String, dynamic>? responsePayload;
  final DateTime createdAt;

  const XenditLogModel({
    required this.id,
    this.loanId,
    this.paymentId,
    this.disbursementId,
    required this.type,
    required this.xenditReferenceId,
    required this.status,
    required this.amount,
    this.requestPayload,
    this.responsePayload,
    required this.createdAt,
  });

  factory XenditLogModel.fromJson(Map<String, dynamic> json) {
    return XenditLogModel(
      id: json['id'] ?? '',
      loanId: json['loan_id'],
      paymentId: json['payment_id'],
      disbursementId: json['disbursement_id'],
      type: json['type'] ?? '',
      xenditReferenceId: json['xendit_reference_id'] ?? '',
      status: json['status'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      requestPayload: json['request_payload'] as Map<String, dynamic>?,
      responsePayload: json['response_payload'] as Map<String, dynamic>?,
      createdAt: json['created_at'] != null
          ? parseManila(json['created_at'])!
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'loan_id': loanId,
        'payment_id': paymentId,
        'disbursement_id': disbursementId,
        'type': type,
        'xendit_reference_id': xenditReferenceId,
        'status': status,
        'amount': amount,
        'request_payload': requestPayload,
        'response_payload': responsePayload,
        'created_at': createdAt.toIso8601String(),
      };
}
