// lib/data/models/collection_assignment_model.dart
class CollectionAssignmentModel {
  final String id;
  final String loanScheduleId;
  final String? riderId;
  final String? assignedBy;
  final String status;
  final String collectionType;
  final double? amountCollected;
  final double? requestedAmount;
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
  final String? flatLoanNumber;
  final String? flatLenderName;
  final String? flatLenderPhone;
  final String? flatLenderGcash;
  final List<dynamic>? flatLenderAddresses;
  final String? flatRiderName;

  const CollectionAssignmentModel({
    required this.id,
    required this.loanScheduleId,
    this.riderId,
    this.assignedBy,
    required this.status,
    this.collectionType = 'rider',
    this.amountCollected,
    this.requestedAmount,
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
    this.flatLoanNumber,
    this.flatLenderName,
    this.flatLenderPhone,
    this.flatLenderGcash,
    this.flatLenderAddresses,
    this.flatRiderName,
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
        requestedAmount: (json['requested_amount'] as num?)?.toDouble(),
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
        flatLoanNumber: json['loan_number'],
        flatLenderName: json['lender_name'],
        flatLenderPhone: json['lender_phone'],
        flatLenderGcash: json['lender_gcash'],
        flatLenderAddresses:
            (json['lender_addresses'] as List?)?.cast<dynamic>(),
        flatRiderName: json['rider_name'],
      );

  String get riderName {
    if (flatRiderName != null && flatRiderName!.isNotEmpty) return flatRiderName!;
    // The embed shape is rider: {id, users: {first_name, last_name}} — the
    // names live under users, not at the root of the rider object.
    final users = rider?['users'];
    if (users is Map) {
      return '${users['first_name'] ?? ''} ${users['last_name'] ?? ''}'.trim();
    }
    return '';
  }

  String get assignedByName {
    if (assignedByUser == null) return '';
    return '${assignedByUser!['first_name'] ?? ''} ${assignedByUser!['last_name'] ?? ''}'
        .trim();
  }

  String get loanNumber {
    if (flatLoanNumber != null && flatLoanNumber!.isNotEmpty) return flatLoanNumber!;
    return loanSchedule?['loan']?['loan_number'] ?? '';
  }

  String get lenderName {
    if (flatLenderName != null && flatLenderName!.isNotEmpty) return flatLenderName!;
    final l = loanSchedule?['loan']?['lender_profiles']?['users'];
    if (l == null) return '';
    return '${l['first_name'] ?? ''} ${l['last_name'] ?? ''}'.trim();
  }

  String get lenderPhone {
    if (flatLenderPhone != null && flatLenderPhone!.isNotEmpty) return flatLenderPhone!;
    return loanSchedule?['loan']?['lender_profiles']?['users']
            ?['phone_number'] ??
        '';
  }

  String get lenderGcash {
    if (flatLenderGcash != null && flatLenderGcash!.isNotEmpty) return flatLenderGcash!;
    return loanSchedule?['loan']?['lender_profiles']?['gcash_number'] ?? '';
  }

  List<dynamic> get lenderAddresses {
    if (flatLenderAddresses != null) return flatLenderAddresses!;
    final users = loanSchedule?['loan']?['lender_profiles']?['users'];
    final list = users is Map<String, dynamic> ? users['addresses'] : null;
    if (list is List) return list;
    return const [];
  }

  double get amountDue =>
      (loanSchedule?['amount_due'] as num?)?.toDouble() ?? 0;

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
