// lib/data/models/address_model.dart
import '../../core/utils/helpers.dart';
class AddressModel {
  final String id;
  final String userId;
  final String addressType;
  final String street;
  final String barangay;
  final String city;
  final String province;
  final String zipCode;
  final double? latitude;
  final double? longitude;
  final bool isPrimary;
  final DateTime createdAt;

  const AddressModel({
    required this.id,
    required this.userId,
    required this.addressType,
    required this.street,
    required this.barangay,
    required this.city,
    required this.province,
    required this.zipCode,
    this.latitude,
    this.longitude,
    required this.isPrimary,
    required this.createdAt,
  });

  factory AddressModel.fromJson(Map<String, dynamic> json) {
    return AddressModel(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      addressType: json['address_type'] ?? 'home',
      street: json['street'] ?? '',
      barangay: json['barangay'] ?? '',
      city: json['city'] ?? '',
      province: json['province'] ?? '',
      zipCode: json['zip_code'] ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      isPrimary: parseBool(json['is_primary'], fallback: false),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'address_type': addressType,
        'street': street,
        'barangay': barangay,
        'city': city,
        'province': province,
        'zip_code': zipCode,
        'latitude': latitude,
        'longitude': longitude,
        'is_primary': isPrimary,
      };

  String get fullAddress => '$street, $barangay, $city, $province $zipCode';
}
