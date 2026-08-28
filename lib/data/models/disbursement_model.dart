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

  // Forward-compat: canonical columns are method_id + status_id (uuid FK -> lookup.id).
  static String _resolveCode(Map<String, dynamic> json, String codeKey, String idKey, String joinKey) {
    final code = json[codeKey];
    if (code is String && code.isNotEmpty) return code;
    final join = json[joinKey];
    if (join is Map && join['code'] is String && (join['code'] as String).isNotEmpty) return join['code'] as String;
    final id = json[idKey];
    if (id is String && id.isNotEmpty) return id;
    return '';
  }

  factory DisbursementModel.fromJson(Map<String, dynamic> json) =>
      DisbursementModel(
        id: json['id'] ?? '',
        loanId: json['loan_id'] ?? '',
        method: _resolveCode(json, 'method', 'method_id', 'disbursement_methods').isNotEmpty
            ? _resolveCode(json, 'method', 'method_id', 'disbursement_methods')
            : 'gcash',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        status: _resolveCode(json, 'status', 'status_id', 'disbursement_statuses').isNotEmpty
            ? _resolveCode(json, 'status', 'status_id', 'disbursement_statuses')
            : 'pending',
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
