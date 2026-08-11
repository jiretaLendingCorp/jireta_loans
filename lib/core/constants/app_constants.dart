// lib/core/constants/app_constants.dart
class AppConstants {
  AppConstants._();

  static const String companyName = 'Jireta Loans & Credit Corp 1966';
  static const String companyShortName = 'Jireta Loans';
  static const String appVersion = '1.0.0';

  static const int connectTimeoutMs = 30000;
  static const int receiveTimeoutMs = 30000;
  static const int sendTimeoutMs = 30000;

  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  static const int otpLength = 6;
  static const int otpResendSeconds = 60;

  static const int locationUpdateIntervalSeconds = 30;

  static const String termsAcceptedKey = 'terms_accepted';
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userIdKey = 'user_id';
  static const String userRoleKey = 'user_role';

  static const String authRefreshPath = 'auth-session?fn=refresh-session';

  static const String roleHeadManager = 'head_manager';
  static const String roleEmployee = 'employee';
  static const String roleRider = 'rider';
  static const String roleLender = 'lender';

  static const String loanStatusPending = 'pending';
  static const String loanStatusUnderReview = 'under_review';
  static const String loanStatusCiRequired = 'ci_required';
  static const String loanStatusCiAssigned = 'ci_assigned';
  static const String loanStatusCiCompleted = 'ci_completed';
  static const String loanStatusApproved = 'approved';
  static const String loanStatusActive = 'active';
  static const String loanStatusCompleted = 'completed';
  static const String loanStatusRejected = 'rejected';
  static const String loanStatusCancelled = 'cancelled';
  static const String loanStatusOverdue = 'overdue';

  static const String kycStatusPending = 'pending';
  static const String kycStatusSubmitted = 'submitted';
  static const String kycStatusVerified = 'verified';
  static const String kycStatusRejected = 'rejected';
}
