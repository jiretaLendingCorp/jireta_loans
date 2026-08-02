// lib/domain/entities/ci_entity.dart
class CiEntity {
  final String id;
  final String loanId;
  final String riderId;
  final String assignedBy;
  final String status;
  final String? investigationNotes;
  final String? reportSummary;
  final DateTime? deadline;
  final DateTime? respondedAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  const CiEntity({
    required this.id,
    required this.loanId,
    required this.riderId,
    required this.assignedBy,
    required this.status,
    this.investigationNotes,
    this.reportSummary,
    this.deadline,
    this.respondedAt,
    this.completedAt,
    required this.createdAt,
  });
}
