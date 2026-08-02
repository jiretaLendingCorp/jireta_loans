// lib/domain/entities/employee_profile_entity.dart
class EmployeeProfileEntity {
  final String id;
  final String userId;
  final String? department;
  final String? position;
  final DateTime? hiredAt;
  final String? gender;
  final String? civilStatus;
  final DateTime? dateOfBirth;
  final DateTime createdAt;

  const EmployeeProfileEntity({
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
}
