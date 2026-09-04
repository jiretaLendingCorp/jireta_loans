// lib/data/models/rider_profile_model.dart
import '../../core/utils/helpers.dart';
import '../../core/utils/timezone.dart';
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

  // Forward-compat: vehicle_type varchar is deprecated alias for vehicle_type_id uuid.
  static String? _resolveNullableCode(Map<String, dynamic> json, String codeKey, String idKey, String joinKey) {
    final code = json[codeKey];
    if (code is String && code.isNotEmpty) return code;
    final join = json[joinKey];
    if (join is Map && join['code'] is String && (join['code'] as String).isNotEmpty) return join['code'] as String;
    final id = json[idKey];
    if (id is String && id.isNotEmpty) return id;
    return null;
  }

  factory RiderProfileModel.fromJson(Map<String, dynamic> json) {
    return RiderProfileModel(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      vehicleType: _resolveNullableCode(json, 'vehicle_type', 'vehicle_type_id', 'vehicle_types'),
      plateNumber: json['plate_number'],
      driversLicenseNumber: json['drivers_license_number'],
      driversLicenseExpiry: json['drivers_license_expiry'] != null
          ? parseManila(json['drivers_license_expiry'])
          : null,
      vehicleBrand: json['vehicle_brand'],
      isAvailable: parseBool(json['is_available'], fallback: true),
      riderStatus: json['rider_status'] ?? 'off',
      totalAmountCollected:
          (json['total_amount_collected'] as num?)?.toDouble() ?? 0.0,
      totalCompletedCollections:
          (json['total_completed_collections'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] != null
          ? parseManila(json['created_at'])!
          : DateTime.now(),
    );
  }
}
