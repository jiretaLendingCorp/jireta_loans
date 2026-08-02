// lib/domain/entities/user_entity.dart
class UserEntity {
  final String id;
  final String role;
  final String? email;
  final String? phoneNumber;
  final String firstName;
  final String? middleName;
  final String lastName;
  final String? suffix;
  final String accountStatus;
  final bool forcePasswordChange;
  final String? profilePhotoUrl;
  final DateTime? lastLoginAt;
  final DateTime createdAt;

  const UserEntity({
    required this.id,
    required this.role,
    this.email,
    this.phoneNumber,
    required this.firstName,
    this.middleName,
    required this.lastName,
    this.suffix,
    required this.accountStatus,
    required this.forcePasswordChange,
    this.profilePhotoUrl,
    this.lastLoginAt,
    required this.createdAt,
  });

  String get fullName => [
    firstName,
    middleName,
    lastName,
    suffix,
  ].where((p) => p != null && p.isNotEmpty).join(' ');

  bool get isActive => accountStatus == 'active';
  bool get isSuspended => accountStatus == 'suspended';
  bool get isArchived => accountStatus == 'archived';
}
