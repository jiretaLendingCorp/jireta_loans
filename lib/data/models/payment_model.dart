// lib/data/models/payment_model.dart
import '../../core/utils/timezone.dart';

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

  // Forward-compat: canonical columns are payment_method_id + status_id (uuid FK).
  // Reads varchar `payment_method`/`status` first (deprecated alias), then joined lookup, then uuid fallback.
  static String _resolveCode(Map<String, dynamic> json, String codeKey, String idKey, String joinKey) {
    final code = json[codeKey];
    if (code is String && code.isNotEmpty) return code;
    final join = json[joinKey];
    if (join is Map && join['code'] is String && (join['code'] as String).isNotEmpty) return join['code'] as String;
    final id = json[idKey];
    if (id is String && id.isNotEmpty) return id;
    return '';
  }

  factory PaymentModel.fromJson(Map<String, dynamic> json) => PaymentModel(
        id: json['id'] ?? '',
        loanId: json['loan_id'] ?? '',
        loanScheduleId: json['loan_schedule_id'],
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        method: _resolveCode(json, 'payment_method', 'payment_method_id', 'payment_methods').isNotEmpty
            ? _resolveCode(json, 'payment_method', 'payment_method_id', 'payment_methods')
            : (json['method'] as String? ?? 'office_cash'),
        status: _resolveCode(json, 'status', 'status_id', 'payment_statuses').isNotEmpty
            ? _resolveCode(json, 'status', 'status_id', 'payment_statuses')
            : 'pending',
        referenceNumber: json['reference_number'],
        xenditPaymentId: json['xendit_payment_id'],
        xenditInvoiceUrl: json['xendit_invoice_url'],
        recordedBy: json['recorded_by'],
        notes: json['notes'],
        idempotencyKey: json['idempotency_key'],
        receiptUrl: json['receipt_url'],
        createdAt: json['created_at'] != null
            ? parseManila(json['created_at'])!
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
      case 'office_cash':
      case 'cash':
        return 'Office';
      case 'rider_collection':
        return 'Rider Collection';
      case 'gcash_xendit':
        return 'GCash';
      default:
        return method.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
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
