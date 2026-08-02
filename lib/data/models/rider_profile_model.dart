// lib/data/models/rider_profile_model.dart
class RiderProfileModel {
  final String id;
  final String userId;
  final String? vehicleType;
  final String? plateNumber;
  final String? driversLicenseNumber;
  final DateTime? driversLicenseExpiry;
  final String? vehicleBrand;
  final bool isAvailable;
  final String riderStatus;
  final double totalAmountCollected;
  final int totalCompletedCollections;
  final DateTime createdAt;

  const RiderProfileModel({
    required this.id,
    required this.userId,
    this.vehicleType,
    this.plateNumber,
    this.driversLicenseNumber,
    this.driversLicenseExpiry,
    this.vehicleBrand,
    required this.isAvailable,
    required this.riderStatus,
    required this.totalAmountCollected,
    required this.totalCompletedCollections,
    required this.createdAt,
  });

  factory RiderProfileModel.fromJson(Map<String, dynamic> json) {
    return RiderProfileModel(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      vehicleType: json['vehicle_type'],
      plateNumber: json['plate_number'],
      driversLicenseNumber: json['drivers_license_number'],
      driversLicenseExpiry: json['drivers_license_expiry'] != null
          ? DateTime.parse(json['drivers_license_expiry'])
          : null,
      vehicleBrand: json['vehicle_brand'],
      isAvailable: json['is_available'] ?? true,
      riderStatus: json['rider_status'] ?? 'off',
      totalAmountCollected:
          (json['total_amount_collected'] as num?)?.toDouble() ?? 0.0,
      totalCompletedCollections:
          (json['total_completed_collections'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }
}
