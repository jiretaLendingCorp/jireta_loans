// lib/data/models/rider_location_model.dart
class RiderLocationModel {
  final String id;
  final String riderId;
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime updatedAt;

  const RiderLocationModel({
    required this.id,
    required this.riderId,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.updatedAt,
  });

  factory RiderLocationModel.fromJson(Map<String, dynamic> json) {
    return RiderLocationModel(
      id: json['id'] ?? '',
      riderId: json['rider_id'] ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
    );
  }
}
