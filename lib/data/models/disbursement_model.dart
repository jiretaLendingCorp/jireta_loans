// lib/data/models/disbursement_model.dart
class DisbursementModel {
  final String id;
  final String loanId;
  final String method;
  final double amount;
  final String status;
  final String? xenditDisbursementId;
  final String? xenditStatus;
  final String? gcashNumber;
  final String? riderId;
  final String? disbursedBy;
  final DateTime? disbursedAt;
  final DateTime? deliveryDate;
  final String? notes;
  final DateTime createdAt;
  final Map<String, dynamic>? loan;
  final Map<String, dynamic>? rider;

  const DisbursementModel({
    required this.id,
    required this.loanId,
    required this.method,
    required this.amount,
    required this.status,
    this.xenditDisbursementId,
    this.xenditStatus,
    this.gcashNumber,
    this.riderId,
    this.disbursedBy,
    this.disbursedAt,
    this.deliveryDate,
    this.notes,
    required this.createdAt,
    this.loan,
    this.rider,
  });

  factory DisbursementModel.fromJson(Map<String, dynamic> json) =>
      DisbursementModel(
        id: json['id'] ?? '',
        loanId: json['loan_id'] ?? '',
        method: json['method'] ?? 'gcash',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        status: json['status'] ?? 'pending',
        xenditDisbursementId: json['xendit_disbursement_id'],
        xenditStatus: json['xendit_status'],
        gcashNumber: json['gcash_number'],
        riderId: json['rider_id'],
        disbursedBy: json['disbursed_by'],
        disbursedAt: json['disbursed_at'] != null
            ? DateTime.parse(json['disbursed_at'])
            : null,
        deliveryDate: json['delivery_date'] != null
            ? DateTime.parse(json['delivery_date'])
            : null,
        notes: json['notes'],
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'])
            : DateTime.now(),
        loan: json['loan'] as Map<String, dynamic>?,
        rider: json['rider'] as Map<String, dynamic>?,
      );

  String get loanNumber => loan?['loan_number'] ?? '';
  String get lenderName {
    final flat = loan?['lender_name'] as String?;
    if (flat != null && flat.trim().isNotEmpty) return flat;
    final lp = loan?['lender_profiles'] as Map<String, dynamic>?;
    final u = lp?['users'] as Map<String, dynamic>?;
    if (u == null) return '';
    return '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
  }

  String get methodLabel {
    switch (method) {
      case 'gcash':
        return 'GCash';
      case 'office_cash':
        return 'Office Cash';
      case 'rider_delivery':
        return 'Rider Delivery';
      default:
        return method;
    }
  }

  String get disbursementMethod => method;
  String get reference => xenditDisbursementId ?? '';
}
