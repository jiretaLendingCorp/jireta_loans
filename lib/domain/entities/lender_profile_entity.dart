// lib/domain/entities/lender_profile_entity.dart
class LenderProfileEntity {
  final String id;
  final String userId;
  final String? gender;
  final String? civilStatus;
  final DateTime? dateOfBirth;
  final String? employmentType;
  final String? employerName;
  final double? monthlyIncome;
  final String? gcashNumber;
  final String kycStatus;
  final bool isBlacklisted;
  final DateTime createdAt;

  const LenderProfileEntity({
    required this.id,
    required this.userId,
    this.gender,
    this.civilStatus,
    this.dateOfBirth,
    this.employmentType,
    this.employerName,
    this.monthlyIncome,
    this.gcashNumber,
    required this.kycStatus,
    required this.isBlacklisted,
    required this.createdAt,
  });

  bool get isKycVerified => kycStatus == 'verified';
  bool get isKycPending => kycStatus == 'pending' || kycStatus == 'submitted';
}
