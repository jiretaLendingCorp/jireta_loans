// lib/domain/entities/loan_entity.dart
class LoanEntity {
  final String id;
  final String loanNumber;
  final String lenderId;
  final String? lenderName;
  final double principalAmount;
  final double interestRate;
  final double interestAmount;
  final double totalPayable;
  final double outstandingBalance;
  final String frequency;
  final int termDays;
  final int termPeriods;
  final DateTime? releaseDate;
  final DateTime? dueDate;
  final String status;
  final String? rejectionReason;
  final bool penaltyApplied;
  final String? disbursementMethod;
  final DateTime? disbursedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LoanEntity({
    required this.id,
    required this.loanNumber,
    required this.lenderId,
    this.lenderName,
    required this.principalAmount,
    required this.interestRate,
    required this.interestAmount,
    required this.totalPayable,
    required this.outstandingBalance,
    required this.frequency,
    required this.termDays,
    required this.termPeriods,
    this.releaseDate,
    this.dueDate,
    required this.status,
    this.rejectionReason,
    required this.penaltyApplied,
    this.disbursementMethod,
    this.disbursedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isCompleted => status == 'completed';
  bool get isOverdue => status == 'overdue';
  bool get isRejected => status == 'rejected';
}
