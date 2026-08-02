// lib/domain/entities/collection_assignment_entity.dart
class CollectionAssignmentEntity {
  final String id;
  final String loanId;
  final String? loanScheduleId;
  final String riderId;
  final String assignedBy;
  final String status;
  final DateTime? collectionSchedule;
  final String? notes;
  final double? amountCollected;
  final String? proofPhoto;
  final String? borrowerSignature;
  final String? collectionPhoto;
  final double? collectionLat;
  final double? collectionLng;
  final DateTime? respondedAt;
  final DateTime createdAt;

  const CollectionAssignmentEntity({
    required this.id,
    required this.loanId,
    this.loanScheduleId,
    required this.riderId,
    required this.assignedBy,
    required this.status,
    this.collectionSchedule,
    this.notes,
    this.amountCollected,
    this.proofPhoto,
    this.borrowerSignature,
    this.collectionPhoto,
    this.collectionLat,
    this.collectionLng,
    this.respondedAt,
    required this.createdAt,
  });
}
