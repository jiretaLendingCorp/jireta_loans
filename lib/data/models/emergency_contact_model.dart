// lib/data/models/emergency_contact_model.dart
class EmergencyContactModel {
  final String id;
  final String userId;
  final String name;
  final String relationship;
  final String phone;
  final String? address;
  final DateTime createdAt;

  const EmergencyContactModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.relationship,
    required this.phone,
    this.address,
    required this.createdAt,
  });

  factory EmergencyContactModel.fromJson(Map<String, dynamic> json) {
    return EmergencyContactModel(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      name: json['name'] ?? '',
      relationship: json['relationship'] ?? '',
      phone: json['phone'] ?? '',
      address: json['address'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }
}
