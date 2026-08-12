// lib/data/models/lender_profile_model.dart
class LenderProfileModel {
  final String id;
  final String userId;
  final String? gender;
  final String? civilStatus;
  final DateTime? dateOfBirth;
  final String? employmentType;
  final String? employerName;
  final double? monthlyIncome;
  final String? gcashNumber;
  final String accountUpgradeStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LenderProfileModel({
    required this.id,
    required this.userId,
    this.gender,
    this.civilStatus,
    this.dateOfBirth,
    this.employmentType,
    this.employerName,
    this.monthlyIncome,
    this.gcashNumber,
    required this.accountUpgradeStatus,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LenderProfileModel.fromJson(Map<String, dynamic> json) {
    return LenderProfileModel(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      gender: json['gender'],
      civilStatus: json['civil_status'],
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.parse(json['date_of_birth'])
          : null,
      employmentType: json['employment_type'],
      employerName: json['employer_name'],
      monthlyIncome: (json['monthly_income'] as num?)?.toDouble(),
      gcashNumber: json['gcash_number'],
      accountUpgradeStatus: json['account_upgrade_status'] ?? 'not_submitted',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
    );
  }

  bool get isAccountUpgradeVerified => accountUpgradeStatus == 'verified';
  bool get isAccountUpgradePending => accountUpgradeStatus == 'pending';
  bool get isAccountUpgradeSubmitted => accountUpgradeStatus == 'submitted';
  bool get isAccountUpgradeRejected => accountUpgradeStatus == 'rejected';
}
