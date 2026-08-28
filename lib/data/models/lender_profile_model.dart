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

  // Forward-compat: varchar deprecated, uuid *_id canonical (trigger-synced).
  static String? _resolveNullableCode(Map<String, dynamic> json, String codeKey, String idKey, String joinKey) {
    final code = json[codeKey];
    if (code is String && code.isNotEmpty) return code;
    final join = json[joinKey];
    if (join is Map && join['code'] is String && (join['code'] as String).isNotEmpty) return join['code'] as String;
    final id = json[idKey];
    if (id is String && id.isNotEmpty) return id;
    return null;
  }

  factory LenderProfileModel.fromJson(Map<String, dynamic> json) {
    return LenderProfileModel(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      gender: _resolveNullableCode(json, 'gender', 'gender_id', 'gender_types'),
      civilStatus: _resolveNullableCode(json, 'civil_status', 'civil_status_id', 'civil_statuses'),
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.parse(json['date_of_birth'])
          : null,
      employmentType: _resolveNullableCode(json, 'employment_type', 'employment_type_id', 'employment_types'),
      employerName: json['employer_name'],
      monthlyIncome: (json['monthly_income'] as num?)?.toDouble(),
      gcashNumber: json['gcash_number'],
      accountUpgradeStatus: _resolveNullableCode(json, 'account_upgrade_status', 'account_upgrade_status_id', 'account_upgrade_statuses') ?? 'not_submitted',
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
