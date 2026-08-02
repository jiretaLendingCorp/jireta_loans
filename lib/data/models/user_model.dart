// lib/data/models/user_model.dart
import '../../domain/entities/user_entity.dart';

class UserModel extends UserEntity {
  final String? department;
  final String? position;
  final String? gender;
  final String? civilStatus;
  final String? plateNumber;
  final String? driversLicenseNumber;
  final String? vehicleBrand;
  final String? vehicleType;

  const UserModel({
    required super.id,
    required super.role,
    super.email,
    super.phoneNumber,
    required super.firstName,
    super.middleName,
    required super.lastName,
    super.suffix,
    required super.accountStatus,
    required super.forcePasswordChange,
    super.profilePhotoUrl,
    super.lastLoginAt,
    required super.createdAt,
    this.department,
    this.position,
    this.gender,
    this.civilStatus,
    this.plateNumber,
    this.driversLicenseNumber,
    this.vehicleBrand,
    this.vehicleType,
  });

  String get phone => phoneNumber ?? '';

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      role: json['role'] ?? json['roles']?['name'] ?? '',
      email: json['email'],
      phoneNumber: json['phone_number'] ?? json['phone'],
      firstName: json['first_name'] ?? '',
      middleName: json['middle_name'],
      lastName: json['last_name'] ?? '',
      suffix: json['suffix'],
      accountStatus: json['account_status'] ?? 'active',
      forcePasswordChange: json['force_password_change'] ?? false,
      profilePhotoUrl: json['profile_photo_url'],
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.parse(json['last_login_at'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      department: json['department'],
      position: json['position'],
      gender: json['gender'],
      civilStatus: json['civil_status'],
      plateNumber: json['plate_number'],
      driversLicenseNumber:
          json['drivers_license_number'] ?? json['license_number'],
      vehicleBrand: json['vehicle_brand'],
      vehicleType: json['vehicle_type'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'email': email,
    'phone_number': phoneNumber,
    'first_name': firstName,
    'middle_name': middleName,
    'last_name': lastName,
    'suffix': suffix,
    'account_status': accountStatus,
    'force_password_change': forcePasswordChange,
    'profile_photo_url': profilePhotoUrl,
    'created_at': createdAt.toIso8601String(),
    'department': department,
    'position': position,
    'gender': gender,
    'civil_status': civilStatus,
    'plate_number': plateNumber,
    'drivers_license_number': driversLicenseNumber,
    'vehicle_brand': vehicleBrand,
    'vehicle_type': vehicleType,
  };

  UserModel copyWith({
    String? role,
    String? email,
    String? phoneNumber,
    String? firstName,
    String? middleName,
    String? lastName,
    String? suffix,
    String? accountStatus,
    bool? forcePasswordChange,
    String? profilePhotoUrl,
  }) {
    return UserModel(
      id: id,
      role: role ?? this.role,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      suffix: suffix ?? this.suffix,
      accountStatus: accountStatus ?? this.accountStatus,
      forcePasswordChange: forcePasswordChange ?? this.forcePasswordChange,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      lastLoginAt: lastLoginAt,
      createdAt: createdAt,
    );
  }
}
