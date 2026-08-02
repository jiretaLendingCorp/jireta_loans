// lib/domain/entities/penalty_log_entity.dart
class PenaltyLogEntity {
  final String id;
  final String loanId;
  final String? loanNumber;
  final String? lenderName;
  final double basisAmount;
  final double penaltyRate;
  final double penaltyAmount;
  final String appliedById;
  final String? appliedByName;
  final DateTime createdAt;

  const PenaltyLogEntity({
    required this.id,
    required this.loanId,
    this.loanNumber,
    this.lenderName,
    required this.basisAmount,
    required this.penaltyRate,
    required this.penaltyAmount,
    required this.appliedById,
    this.appliedByName,
    required this.createdAt,
  });
}
