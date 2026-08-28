// lib/data/models/loan_model.dart
import '../../domain/entities/loan_entity.dart';
import '../../core/utils/helpers.dart';

class LoanModel extends LoanEntity {
  final Map<String, dynamic>? lenderProfile;
  final List<Map<String, dynamic>>? schedules;
  final List<Map<String, dynamic>>? payments;
  final String? assignedRiderName;
  final String? ciStatus;
  final String? disbursementAccount;
  final String? purpose;
  final Map<String, dynamic>? lenderAddress;
  final bool riderDeliveryAssigned;
  final double _installmentAmount;

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
    required super.termPeriods,
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
    this.disbursementAccount,
    this.purpose,
    this.lenderAddress,
    this.riderDeliveryAssigned = false,
    double installmentAmount = 0,
  }) : _installmentAmount = installmentAmount;

  // Forward-compat: canonical DB columns are payment_frequency_id + status_id (uuid FK -> lookup.id).
  // Edge still sends varchar `payment_frequency`/`status` (deprecated alias, trigger-synced),
  // but after v2 drop the canonical views v_loans_canonical will JOIN code for display.
  // This factory therefore reads varchar first, then joined lookup object, then uuid fallback.
  static String _resolveCode(Map<String, dynamic> json, String codeKey, String idKey, String joinKey) {
    final code = json[codeKey];
    if (code is String && code.isNotEmpty) return code;
    final join = json[joinKey];
    if (join is Map && join['code'] is String && (join['code'] as String).isNotEmpty) {
      return join['code'] as String;
    }
    final id = json[idKey];
    if (id is String && id.isNotEmpty) return id; // uuid fallback (v2 raw select); UI should map via lookup if needed
    return '';
  }

  factory LoanModel.fromJson(Map<String, dynamic> json) {
    return LoanModel(
      id: json['id'],
      loanNumber: json['loan_number'] ?? '',
      lenderId: json['lender_id'] ?? '',
      lenderName: _parseLenderName(json),
      principalAmount: _toDouble(json['principal_amount']),
      interestRate: _toDouble(json['interest_rate']),
      interestAmount: _toDouble(json['interest_amount']),
      totalPayable: _toDouble(json['total_payable']),
      outstandingBalance: _toDouble(json['outstanding_balance']),
      frequency: _resolveCode(json, 'payment_frequency', 'payment_frequency_id', 'payment_frequencies').isNotEmpty
          ? _resolveCode(json, 'payment_frequency', 'payment_frequency_id', 'payment_frequencies')
          : (json['frequency'] as String? ?? 'monthly'),
      termDays: (json['term_days'] as num?)?.toInt() ?? 0,
      termPeriods: (json['term_periods'] as num?)?.toInt() ?? 0,
      releaseDate: json['release_date'] != null
          ? DateTime.parse(json['release_date'])
          : null,
      dueDate:
          json['due_date'] != null ? DateTime.parse(json['due_date']) : null,
      status: _resolveCode(json, 'status', 'status_id', 'loan_statuses').isNotEmpty
          ? _resolveCode(json, 'status', 'status_id', 'loan_statuses')
          : 'pending',
      rejectionReason: json['rejection_reason'],
      penaltyApplied: parseBool(json['penalty_applied'], fallback: false),
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
      schedules:
          (json['loan_schedules'] as List?)?.cast<Map<String, dynamic>>(),
      payments: (json['payments'] as List?)?.cast<Map<String, dynamic>>(),
      assignedRiderName: json['assigned_rider_name'],
      ciStatus: json['ci_status'],
      disbursementAccount: json['disbursement_account'],
      purpose: json['purpose'],
      lenderAddress: json['lender_address'],
      riderDeliveryAssigned: parseBool(json['rider_delivery_assigned'], fallback: false),
      installmentAmount: _toDouble(json['installment_amount']),
    );
  }

  static double _toDouble(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

  static String? _parseLenderName(Map<String, dynamic> json) {
    final embedded = json['lender'];
    if (embedded is Map) {
      final first = embedded['first_name'];
      final last = embedded['last_name'];
      if (first != null || last != null) {
        return '${first ?? ''} ${last ?? ''}'.trim();
      }
    }
    final profile = json['lender_profile'];
    if (profile is Map) {
      final users = profile['users'];
      if (users is Map) {
        final first = users['first_name'];
        final last = users['last_name'];
        if (first != null || last != null) {
          return '${first ?? ''} ${last ?? ''}'.trim();
        }
      }
    }
    final name = json['lender_name'];
    if (name is String && name.trim().isNotEmpty) return name.trim();
    return null;
  }

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

  /// Installment (per-period) amount. Falls back to the first schedule's due
  /// amount when the loan payload omits `installment_amount`.
  double get installmentAmount => _installmentAmount > 0
      ? _installmentAmount
      : ((schedules?.isNotEmpty ?? false)
          ? ((schedules!.first['amount_due'] as num?)?.toDouble() ?? 0.0)
          : 0.0);

  String get paymentFrequency => frequency;

  String get termUnit {
    switch (frequency) {
      case 'daily':
        return 'days';
      case 'weekly':
        return 'weeks';
      default:
        return 'months';
    }
  }

  /// Human-readable chosen repayment term, e.g. "6 weeks" or "60 days".
  /// Falls back to the default full term (`term_days`) when the borrower kept
  /// the maximum allowed number of periods.
  String get termLabel {
    if (termPeriods > 0) return '$termPeriods $termUnit';
    final sched = schedules;
    if (sched != null && sched.isNotEmpty) return '${sched.length} $termUnit';
    return '$termDays days';
  }

  /// Number of installments the borrower chose to pay.
  int get numberOfPayments => termPeriods;

  /// Status shown in lists/details. Once a delivery rider is assigned to an
  /// approved loan (loan stays `approved` until the rider completes delivery),
  /// surface it as `rider_delivery_assigned` so staff see the real state.
  String get displayStatus => (riderDeliveryAssigned && status == 'approved')
      ? 'rider_delivery_assigned'
      : status;

  String get formattedLenderAddress {
    final a = lenderAddress;
    if (a == null) return '';
    final parts = [
      a['street'],
      a['barangay'],
      a['city'],
      a['province'],
    ]
        .where((e) => e != null && e.toString().isNotEmpty)
        .map((e) => e.toString())
        .toList();
    return parts.join(', ');
  }
}
