// lib/domain/entities/disbursement_entity.dart
class DisbursementEntity {
  final String id;
  final String loanId;
  final double amount;
  final String method;
  final String status;
  final String? xenditDisbursementId;
  final String? xenditStatus;
  final String? assignedRiderId;
  final String? disbursedBy;
  final DateTime? disbursedAt;
  final DateTime createdAt;

  const DisbursementEntity({
    required this.id,
    required this.loanId,
    required this.amount,
    required this.method,
    required this.status,
    this.xenditDisbursementId,
    this.xenditStatus,
    this.assignedRiderId,
    this.disbursedBy,
    this.disbursedAt,
    required this.createdAt,
  });
}
