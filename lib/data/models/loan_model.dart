// lib/data/models/loan_model.dart
import '../../domain/entities/loan_entity.dart';

class LoanModel extends LoanEntity {
  final Map<String, dynamic>? lenderProfile;
  final List<Map<String, dynamic>>? schedules;
  final List<Map<String, dynamic>>? payments;
  final String? assignedRiderName;
  final String? ciStatus;

  const LoanModel({
    required super.id,
    required super.loanNumber,
    required super.lenderId,
    super.lenderName,
    required super.principalAmount,
    required super.interestRate,
    required super.interestAmount,
    required super.totalPayable,
    required super.outstandingBalance,
    required super.frequency,
    required super.termDays,
    super.releaseDate,
    super.dueDate,
    required super.status,
    super.rejectionReason,
    required super.penaltyApplied,
    super.disbursementMethod,
    super.disbursedAt,
    required super.createdAt,
    required super.updatedAt,
    this.lenderProfile,
    this.schedules,
    this.payments,
    this.assignedRiderName,
    this.ciStatus,
  });

  factory LoanModel.fromJson(Map<String, dynamic> json) {
    return LoanModel(
      id: json['id'],
      loanNumber: json['loan_number'] ?? '',
      lenderId: json['lender_id'] ?? '',
      lenderName: json['lender']?['first_name'] != null
          ? '${json['lender']['first_name']} ${json['lender']['last_name']}'
          : null,
      principalAmount: _toDouble(json['principal_amount']),
      interestRate: _toDouble(json['interest_rate']),
      interestAmount: _toDouble(json['interest_amount']),
      totalPayable: _toDouble(json['total_payable']),
      outstandingBalance: _toDouble(json['outstanding_balance']),
      frequency: json['frequency'] ?? 'monthly',
      termDays: (json['term_days'] as num?)?.toInt() ?? 0,
      releaseDate: json['release_date'] != null
          ? DateTime.parse(json['release_date'])
          : null,
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'])
          : null,
      status: json['status'] ?? 'pending',
      rejectionReason: json['rejection_reason'],
      penaltyApplied: json['penalty_applied'] ?? false,
      disbursementMethod: json['disbursement_method'],
      disbursedAt: json['disbursed_at'] != null
          ? DateTime.parse(json['disbursed_at'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
      lenderProfile: json['lender_profile'],
      schedules: (json['loan_schedules'] as List?)
          ?.cast<Map<String, dynamic>>(),
      payments: (json['payments'] as List?)?.cast<Map<String, dynamic>>(),
      assignedRiderName: json['assigned_rider_name'],
      ciStatus: json['ci_status'],
    );
  }

  static double _toDouble(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

  String get lenderFirstName {
    final lp = lenderProfile;
    if (lp != null) return lp['first_name'] as String? ?? '';
    final ln = lenderName;
    if (ln == null || ln.isEmpty) return '';
    return ln.split(' ').first;
  }

  String get lenderLastName {
    final lp = lenderProfile;
    if (lp != null) return lp['last_name'] as String? ?? '';
    final ln = lenderName;
    if (ln == null || ln.isEmpty) return '';
    final parts = ln.split(' ');
    return parts.length > 1 ? parts.sublist(1).join(' ') : '';
  }

  String get paymentFrequency => frequency;
}
