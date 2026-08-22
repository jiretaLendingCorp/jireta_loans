// lib/data/models/tracked_rider_model.dart
/// A rider the lender can currently track live on the home screen.
///
/// Only exists for assignments the rider has ACCEPTED (or is actively
/// working on): an accepted collection (tracking ends once it is recorded —
/// the cash handover with the lender is done at that point), an
/// accepted/in_progress credit-investigation, or an in-flight rider-delivery
/// disbursement. Mirrors the payload of `location-manage?fn=list-tracked`.
class TrackedRiderModel {
  final String riderId;
  final String riderName;
  final String assignmentType;
  final String assignmentId;
  final String assignmentStatus;
  final String loanId;
  final String loanNumber;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final DateTime? locationUpdatedAt;
  final bool isStale;

  const TrackedRiderModel({
    required this.riderId,
    required this.riderName,
    required this.assignmentType,
    required this.assignmentId,
    required this.assignmentStatus,
    required this.loanId,
    required this.loanNumber,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.locationUpdatedAt,
    this.isStale = false,
  });

  bool get hasLocation => latitude != null && longitude != null;

  factory TrackedRiderModel.fromJson(Map<String, dynamic> json) {
    return TrackedRiderModel(
      riderId: json['rider_id'] ?? '',
      riderName: json['rider_name'] ?? '',
      assignmentType: json['assignment_type'] ?? '',
      assignmentId: json['assignment_id'] ?? '',
      assignmentStatus: json['assignment_status'] ?? '',
      loanId: json['loan_id'] ?? '',
      loanNumber: json['loan_number'] ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      locationUpdatedAt: json['location_updated_at'] != null
          ? DateTime.tryParse(json['location_updated_at'])
          : null,
      isStale: json['is_stale'] == true,
    );
  }
}
