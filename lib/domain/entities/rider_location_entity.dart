// lib/domain/entities/rider_location_entity.dart
class RiderLocationEntity {
  final String riderId;
  final double latitude;
  final double longitude;
  final DateTime updatedAt;

  const RiderLocationEntity({
    required this.riderId,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
  });
}
