// lib/domain/entities/emergency_contact_entity.dart
class EmergencyContactEntity {
  final String id;
  final String userId;
  final String fullName;
  final String relationship;
  final String contactNumber;
  final String? address;
  final DateTime createdAt;

  const EmergencyContactEntity({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.relationship,
    required this.contactNumber,
    this.address,
    required this.createdAt,
  });
}
