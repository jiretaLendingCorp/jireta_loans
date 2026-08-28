// lib/data/models/user_model.dart
import '../../domain/entities/user_entity.dart';
import '../../core/utils/helpers.dart';

class UserModel extends UserEntity {
  final String? department;
  final String? position;
  final String? gender;
  final String? civilStatus;
  final String? plateNumber;
  final String? driversLicenseNumber;
  final String? vehicleBrand;
  final String? vehicleType;
  final String? employmentType;
  final String? employerName;
  final double? monthlyIncome;
  final String? gcashNumber;
  final String? accountUpgradeStatus;
  final DateTime? dateOfBirth;
  final String? sourceOfFunds;
  final String? streetAddress;
  final String? barangay;
  final String? city;
  final String? province;
  final String? zipCode;
  final List<Map<String, dynamic>> emergencyContacts;

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
    this.employmentType,
    this.employerName,
    this.monthlyIncome,
    this.gcashNumber,
    this.accountUpgradeStatus,
    this.dateOfBirth,
    this.sourceOfFunds,
    this.streetAddress,
    this.barangay,
    this.city,
    this.province,
    this.zipCode,
    this.emergencyContacts = const [],
  });

  String get phone => phoneNumber ?? '';

  // Forward-compat helper: varchar `code` is deprecated alias for uuid *_id.
  // Reads code first (still sent by Edge), then joined lookup, then uuid fallback.
  static String? _resolveNullableCode(Map<String, dynamic> json, String codeKey, String idKey, String joinKey) {
    final code = json[codeKey];
    if (code is String && code.isNotEmpty) return code;
    final join = json[joinKey];
    if (join is Map && join['code'] is String && (join['code'] as String).isNotEmpty) return join['code'] as String;
    final id = json[idKey];
    if (id is String && id.isNotEmpty) return id;
    return null;
  }

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
      accountStatus: _resolveNullableCode(json, 'account_status', 'account_status_id', 'user_account_statuses') ?? 'active',
      forcePasswordChange: parseBool(json['force_password_change'], fallback: false),
      profilePhotoUrl: json['profile_photo_url'],
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.parse(json['last_login_at'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      department: json['department'],
      position: json['position'],
      gender: _resolveNullableCode(json, 'gender', 'gender_id', 'gender_types'),
      civilStatus: _resolveNullableCode(json, 'civil_status', 'civil_status_id', 'civil_statuses'),
      plateNumber: json['plate_number'],
      driversLicenseNumber:
          json['drivers_license_number'] ?? json['license_number'],
      vehicleBrand: json['vehicle_brand'],
      vehicleType: _resolveNullableCode(json, 'vehicle_type', 'vehicle_type_id', 'vehicle_types'),
      employmentType: _resolveNullableCode(json, 'employment_type', 'employment_type_id', 'employment_types'),
      employerName: json['employer_name'],
      monthlyIncome: json['monthly_income'] != null
          ? (json['monthly_income'] as num).toDouble()
          : null,
      gcashNumber: json['gcash_number'],
      accountUpgradeStatus: _resolveNullableCode(json, 'account_upgrade_status', 'account_upgrade_status_id', 'account_upgrade_statuses'),
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.tryParse(json['date_of_birth'])
          : null,
      sourceOfFunds: json['source_of_funds'],
      streetAddress: json['street_address'],
      barangay: json['barangay'],
      city: json['city'],
      province: json['province'],
      zipCode: json['zip_code'],
      emergencyContacts: (json['emergency_contacts'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          const [],
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
        'employment_type': employmentType,
        'employer_name': employerName,
        'monthly_income': monthlyIncome,
        'gcash_number': gcashNumber,
        'account_upgrade_status': accountUpgradeStatus,
        'date_of_birth': dateOfBirth?.toIso8601String(),
        'source_of_funds': sourceOfFunds,
        'street_address': streetAddress,
        'barangay': barangay,
        'city': city,
        'province': province,
        'zip_code': zipCode,
        'emergency_contacts': emergencyContacts,
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
      department: department,
      position: position,
      gender: gender,
      civilStatus: civilStatus,
      plateNumber: plateNumber,
      driversLicenseNumber: driversLicenseNumber,
      vehicleBrand: vehicleBrand,
      vehicleType: vehicleType,
      employmentType: employmentType,
      employerName: employerName,
      monthlyIncome: monthlyIncome,
      gcashNumber: gcashNumber,
      accountUpgradeStatus: accountUpgradeStatus,
      dateOfBirth: dateOfBirth,
      sourceOfFunds: sourceOfFunds,
      streetAddress: streetAddress,
      barangay: barangay,
      city: city,
      province: province,
      zipCode: zipCode,
    );
  }
}
