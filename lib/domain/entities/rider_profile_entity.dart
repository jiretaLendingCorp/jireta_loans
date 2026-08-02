// lib/domain/entities/rider_profile_entity.dart
class RiderProfileEntity {
  final String id;
  final String userId;
  final String? vehicleType;
  final String? plateNumber;
  final String? vehicleBrand;
  final String? driversLicenseNumber;
  final DateTime? driversLicenseExpiry;
  final String riderStatus;
  final bool isAvailable;
  final DateTime createdAt;

  const RiderProfileEntity({
    required this.id,
    required this.userId,
    this.vehicleType,
    this.plateNumber,
    this.vehicleBrand,
    this.driversLicenseNumber,
    this.driversLicenseExpiry,
    required this.riderStatus,
    required this.isAvailable,
    required this.createdAt,
  });
}
