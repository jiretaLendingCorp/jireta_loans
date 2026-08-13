// lib/data/models/payment_model.dart
class PaymentModel {
  final String id;
  final String loanId;
  final String? loanScheduleId;
  final double amount;
  final String method;
  final String status;
  final String? referenceNumber;
  final String? xenditPaymentId;
  final String? xenditInvoiceUrl;
  final String? recordedBy;
  final String? notes;
  final String? idempotencyKey;
  final String? receiptUrl;
  final DateTime createdAt;
  final Map<String, dynamic>? loan;
  final Map<String, dynamic>? recordedByUser;

  const PaymentModel({
    required this.id,
    required this.loanId,
    this.loanScheduleId,
    required this.amount,
    required this.method,
    required this.status,
    this.referenceNumber,
    this.xenditPaymentId,
    this.xenditInvoiceUrl,
    this.recordedBy,
    this.notes,
    this.idempotencyKey,
    this.receiptUrl,
    required this.createdAt,
    this.loan,
    this.recordedByUser,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) => PaymentModel(
        id: json['id'] ?? '',
        loanId: json['loan_id'] ?? '',
        loanScheduleId: json['loan_schedule_id'],
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        method: json['method'] ?? 'cash',
        status: json['status'] ?? 'pending',
        referenceNumber: json['reference_number'],
        xenditPaymentId: json['xendit_payment_id'],
        xenditInvoiceUrl: json['xendit_invoice_url'],
        recordedBy: json['recorded_by'],
        notes: json['notes'],
        idempotencyKey: json['idempotency_key'],
        receiptUrl: json['receipt_url'],
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'])
            : DateTime.now(),
        loan: json['loan'] as Map<String, dynamic>?,
        recordedByUser: json['recorded_by_user'] as Map<String, dynamic>?,
      );

  String get loanNumber => loan?['loan_number'] ?? '';
  String get lenderName {
    final l = loan?['lender'];
    if (l == null) return '';
    return '${l['first_name'] ?? ''} ${l['last_name'] ?? ''}'.trim();
  }

  String get recordedByName {
    if (recordedByUser == null) return '';
    return '${recordedByUser!['first_name'] ?? ''} ${recordedByUser!['last_name'] ?? ''}'
        .trim();
  }

  String get methodLabel {
    switch (method) {
      case 'gcash':
        return 'GCash';
      case 'cash':
        return 'Cash';
      case 'office_cash':
        return 'Office Cash';
      default:
        return method;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'verified':
        return 'Verified';
      case 'failed':
        return 'Failed';
      case 'reversed':
        return 'Reversed';
      default:
        return status;
    }
  }
}
