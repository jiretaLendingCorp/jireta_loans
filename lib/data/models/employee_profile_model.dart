// lib/data/models/employee_profile_model.dart
import '../../core/utils/timezone.dart';

class EmployeeProfileModel {
  final String id;
  final String userId;
  final String? position;
  final DateTime? hiredAt;
  final String? gender;
  final String? civilStatus;
  final DateTime? dateOfBirth;
  final DateTime createdAt;

  const EmployeeProfileModel({
    required this.id,
    required this.userId,
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
      position: json['position'],
      hiredAt:
          json['hired_at'] != null ? parseManila(json['hired_at']) : null,
      gender: json['gender'],
      civilStatus: json['civil_status'],
      dateOfBirth: json['date_of_birth'] != null
          ? parseManila(json['date_of_birth'])
          : null,
      createdAt: json['created_at'] != null
          ? parseManila(json['created_at'])!
          : DateTime.now(),
    );
  }
}
