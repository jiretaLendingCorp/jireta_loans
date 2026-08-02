// lib/data/models/employee_profile_model.dart
class EmployeeProfileModel {
  final String id;
  final String userId;
  final String? department;
  final String? position;
  final DateTime? hiredAt;
  final String? gender;
  final String? civilStatus;
  final DateTime? dateOfBirth;
  final DateTime createdAt;

  const EmployeeProfileModel({
    required this.id,
    required this.userId,
    this.department,
    this.position,
    this.hiredAt,
    this.gender,
    this.civilStatus,
    this.dateOfBirth,
    required this.createdAt,
  });

  factory EmployeeProfileModel.fromJson(Map<String, dynamic> json) {
    return EmployeeProfileModel(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      department: json['department'],
      position: json['position'],
      hiredAt:
          json['hired_at'] != null ? DateTime.parse(json['hired_at']) : null,
      gender: json['gender'],
      civilStatus: json['civil_status'],
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.parse(json['date_of_birth'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }
}
