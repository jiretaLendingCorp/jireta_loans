// lib/data/models/co_maker_model.dart
class CoMakerModel {
  final String id;
  final String loanId;
  final String firstName;
  final String lastName;
  final String relationship;
  final String? phone;
  final DateTime? dateOfBirth;
  final String? address;
  final String? signature;
  final DateTime createdAt;

  const CoMakerModel({
    required this.id,
    required this.loanId,
    required this.firstName,
    required this.lastName,
    required this.relationship,
    this.phone,
    this.dateOfBirth,
    this.address,
    this.signature,
    required this.createdAt,
  });

  factory CoMakerModel.fromJson(Map<String, dynamic> json) {
    return CoMakerModel(
      id: json['id'] ?? '',
      loanId: json['loan_id'] ?? '',
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      relationship: json['relationship'] ?? '',
      phone: json['phone_number'] ?? json['phone'],
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.parse(json['date_of_birth'])
          : null,
      address: json['address'],
      signature: json['signature'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  String get fullName => '$firstName $lastName';
}
