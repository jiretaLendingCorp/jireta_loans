// lib/data/models/user_model.dart
import '../../domain/entities/user_entity.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/timezone.dart';

class UserModel extends UserEntity {
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

  /// Composed one-line address (rider_profiles.address). Staff/rider structured
  /// parts come through [streetAddress]/[barangay]/[city]/[province].
  final String? address;
  final List<Map<String, dynamic>> emergencyContacts;
  final bool isWalkIn;
  final Map<String, dynamic>? inOfficeApplication;

  // ── Per-lender payment insights (HM/Employee lender list + details) ──────
  /// CURRENT outstanding balance — sum ng outstanding ng active/overdue loans.
  final double outstandingBalance;
  final int activeLoansCount;
  final int settledLoansCount;

  /// Bilang ng verified payments, at kung ilan ang on-time/late.
  final int verifiedPaymentCount;
  final int onTimePaymentCount;
  final int latePaymentCount;

  /// Pinakamalaking bilang ng araw na nauna ang bayad kaysa sa due date.
  final int maxDaysEarly;

  /// TRUE kapag may verified payments at LAHAT ng bayad ay bago/o sa exactong
  /// due date ng installment (base sa loan term na kinuha ng lender).
  final bool isEarlyPayer;

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
    this.address,
    this.emergencyContacts = const [],
    this.isWalkIn = false,
    this.inOfficeApplication,
    this.outstandingBalance = 0,
    this.activeLoansCount = 0,
    this.settledLoansCount = 0,
    this.verifiedPaymentCount = 0,
    this.onTimePaymentCount = 0,
    this.latePaymentCount = 0,
    this.maxDaysEarly = 0,
    this.isEarlyPayer = false,
  });

  String get phone => phoneNumber ?? '';

  /// Composed na one-line address: `street, barangay, city, province, zip`
  /// (mula sa `addresses` table, primary home address — get-profile). Fallback
  /// ang [`address`] (composed one-liner ng `rider_profiles.address`) kapag
  /// walang structured parts. Ginagamit ng mga Profile screen ng lahat ng role
  /// (HM / Employee / Rider / Lender) para pantay ang format.
  String get formattedAddress {
    final structured = [streetAddress, barangay, city, province, zipCode]
        .where((p) => p != null && p.trim().isNotEmpty)
        .map((p) => p!.trim())
        .toList();
    if (structured.isNotEmpty) return structured.join(', ');
    return (address ?? '').trim();
  }

  /// May balance pa ba ang lender (may active/overdue na loan)?
  bool get hasOutstanding => outstandingBalance > 0;

  /// May verified payment history na ba — basehan ng early-payer badge.
  bool get hasPaymentHistory => verifiedPaymentCount > 0;

  /// Human-readable na paliwanag ng early-payer status para sa details screen.
  String get paymentBehaviorLabel {
    if (!hasPaymentHistory) return 'No payments yet';
    if (isEarlyPayer) {
      return latePaymentCount == 0 && maxDaysEarly > 0
          ? 'Early payer — $onTimePaymentCount/$verifiedPaymentCount on time, '
              'up to $maxDaysEarly day(s) ahead'
          : 'Early payer — all $verifiedPaymentCount payment(s) on time';
    }
    return '$latePaymentCount of $verifiedPaymentCount payment(s) paid late';
  }

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
      // `last_login_at` ay TOTOONG UTC instant (isinusulat ng auth-login /
      // auth-otp / auth-google gamit ang `nowManilaISO()` = `new Date()
      // .toISOString()`, at `DEFAULT now()` para sa legacy rows) — kaya dapat
      // dumaan sa `parseManila` (+8h) tulad ng `created_at`. Kung raw
      // `DateTime.parse` lang, 8 oras na mas maaga ang naipapakitang
      // "Last login" (hal. 12:04 AM imbes na 8:04 AM).
      lastLoginAt: parseManila(json['last_login_at']),
      createdAt: json['created_at'] != null
          ? parseManila(json['created_at'])!
          : DateTime.now(),
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
          ? parseManila(json['date_of_birth'])
          : null,
      sourceOfFunds: json['source_of_funds'],
      streetAddress: json['street_address'],
      barangay: json['barangay'],
      city: json['city'],
      province: json['province'],
      zipCode: json['zip_code'],
      address: json['address'],
      emergencyContacts: (json['emergency_contacts'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          const [],
      isWalkIn: json['is_walk_in'] == true || json['isWalkIn'] == true,
      inOfficeApplication: json['in_office_application'] is Map ? Map<String, dynamic>.from(json['in_office_application'] as Map) : null,
      outstandingBalance:
          (json['outstanding_balance'] as num?)?.toDouble() ?? 0,
      activeLoansCount: (json['active_loans_count'] as num?)?.toInt() ?? 0,
      settledLoansCount: (json['settled_loans_count'] as num?)?.toInt() ?? 0,
      verifiedPaymentCount:
          (json['verified_payment_count'] as num?)?.toInt() ?? 0,
      onTimePaymentCount:
          (json['on_time_payment_count'] as num?)?.toInt() ?? 0,
      latePaymentCount: (json['late_payment_count'] as num?)?.toInt() ?? 0,
      maxDaysEarly: (json['max_days_early'] as num?)?.toInt() ?? 0,
      isEarlyPayer: json['is_early_payer'] == true,
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
        'address': address,
        'emergency_contacts': emergencyContacts,
        'is_walk_in': isWalkIn,
        'in_office_application': inOfficeApplication,
        'outstanding_balance': outstandingBalance,
        'active_loans_count': activeLoansCount,
        'settled_loans_count': settledLoansCount,
        'verified_payment_count': verifiedPaymentCount,
        'on_time_payment_count': onTimePaymentCount,
        'late_payment_count': latePaymentCount,
        'max_days_early': maxDaysEarly,
        'is_early_payer': isEarlyPayer,
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
    String? address,
    bool? isWalkIn,
    Map<String, dynamic>? inOfficeApplication,
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
      address: address ?? this.address,
      emergencyContacts: emergencyContacts,
      isWalkIn: isWalkIn ?? this.isWalkIn,
      inOfficeApplication: inOfficeApplication ?? this.inOfficeApplication,
      outstandingBalance: outstandingBalance,
      activeLoansCount: activeLoansCount,
      settledLoansCount: settledLoansCount,
      verifiedPaymentCount: verifiedPaymentCount,
      onTimePaymentCount: onTimePaymentCount,
      latePaymentCount: latePaymentCount,
      maxDaysEarly: maxDaysEarly,
      isEarlyPayer: isEarlyPayer,
    );
  }
}
