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
  static const String sessionStartedAtKey = 'session_started_at';
  static const String lastActivityKey = 'last_activity_at';

  static const String authRefreshPath = 'auth-session?fn=refresh-session';

  /// Idle session timeout: 10 minutes of inactivity → auto logout.
  /// Any user interaction (tap, scroll, typing) or authenticated API call
  /// bumps the idle deadline forward by 10 minutes.
  static const Duration sessionDuration = Duration(minutes: 10);
  static const int sessionDurationMs = 600000;
  static const int sessionDurationSeconds = 600;

  /// Legacy 1-hour constant kept for migration only (old installs may still
  /// have a JWT-derived startedAt without last_activity_at).
  static const Duration legacySessionDuration = Duration(hours: 1);

  /// Deep link Supabase redirects to after Google OAuth completes on mobile.
  /// Must match the Android intent-filter scheme and the iOS URL scheme.
  static const String googleOAuthRedirectUri =
      'com.jireta.loans://login-callback';

  static const String roleHeadManager = 'head_manager';
  static const String roleEmployee = 'employee';
  static const String roleRider = 'rider';
  static const String roleLender = 'lender';
  /// Borrower alias for [roleLender] — semantically borrower/client (DB VIEW borrower_profiles).
  static const String roleBorrower = roleLender;

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

  static const String accountUpgradeStatusPending = 'pending';
  static const String accountUpgradeStatusSubmitted = 'submitted';
  static const String accountUpgradeStatusVerified = 'verified';
  static const String accountUpgradeStatusRejected = 'rejected';
}
