// lib/data/models/collection_assignment_model.dart
class CollectionAssignmentModel {
  final String id;
  final String loanScheduleId;
  final String? riderId;
  final String? assignedBy;
  final String status;
  final String collectionType;
  final double? amountCollected;
  final String? notes;
  final DateTime? collectionSchedule;
  final DateTime? responseAt;
  final DateTime? completedAt;
  final String? proofPhoto;
  final String? borrowerSignature;
  final String? collectionPhoto;
  final double? locationLat;
  final double? locationLng;
  final String? idempotencyKey;
  final DateTime createdAt;
  final Map<String, dynamic>? loanSchedule;
  final Map<String, dynamic>? rider;
  final Map<String, dynamic>? assignedByUser;

  const CollectionAssignmentModel({
    required this.id,
    required this.loanScheduleId,
    this.riderId,
    this.assignedBy,
    required this.status,
    this.collectionType = 'rider',
    this.amountCollected,
    this.notes,
    this.collectionSchedule,
    this.responseAt,
    this.completedAt,
    this.proofPhoto,
    this.borrowerSignature,
    this.collectionPhoto,
    this.locationLat,
    this.locationLng,
    this.idempotencyKey,
    required this.createdAt,
    this.loanSchedule,
    this.rider,
    this.assignedByUser,
  });

  factory CollectionAssignmentModel.fromJson(Map<String, dynamic> json) =>
      CollectionAssignmentModel(
        id: json['id'] ?? '',
        loanScheduleId: json['loan_schedule_id'] ?? '',
        riderId: json['rider_id'],
        assignedBy: json['assigned_by'],
        status: json['status'] ?? 'pending',
        collectionType: json['collection_type'] ?? 'rider',
        amountCollected: (json['amount_collected'] as num?)?.toDouble(),
        notes: json['notes'],
        collectionSchedule: json['collection_schedule'] != null
            ? DateTime.parse(json['collection_schedule'])
            : null,
        responseAt: json['response_at'] != null
            ? DateTime.parse(json['response_at'])
            : null,
        completedAt: json['completed_at'] != null
            ? DateTime.parse(json['completed_at'])
            : null,
        proofPhoto: json['proof_photo'],
        borrowerSignature: json['borrower_signature'],
        collectionPhoto: json['collection_photo'],
        locationLat: (json['location_lat'] as num?)?.toDouble(),
        locationLng: (json['location_lng'] as num?)?.toDouble(),
        idempotencyKey: json['idempotency_key'],
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'])
            : DateTime.now(),
        loanSchedule: json['loan_schedule'] as Map<String, dynamic>?,
        rider: json['rider'] as Map<String, dynamic>?,
        assignedByUser: json['assigned_by_user'] as Map<String, dynamic>?,
      );

  String get riderName {
    if (rider == null) return '';
    return '${rider!['first_name'] ?? ''} ${rider!['last_name'] ?? ''}'.trim();
  }

  String get assignedByName {
    if (assignedByUser == null) return '';
    return '${assignedByUser!['first_name'] ?? ''} ${assignedByUser!['last_name'] ?? ''}'
        .trim();
  }

  String get loanNumber => loanSchedule?['loan']?['loan_number'] ?? '';

  String get lenderName {
    final l = loanSchedule?['loan']?['lender'];
    if (l == null) return '';
    return '${l['first_name'] ?? ''} ${l['last_name'] ?? ''}'.trim();
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'declined':
        return 'Declined';
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      default:
        return status;
    }
  }
}
