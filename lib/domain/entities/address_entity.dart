// lib/domain/entities/address_entity.dart
class AddressEntity {
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

  const AddressEntity({
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
}
