// lib/core/constants/app_constants.dart
class AppConstants {
  AppConstants._();

  static const String companyName = 'Jireta Loans & Credit Corp 1966';
  static const String companyShortName = 'Jireta Loans';
  static const String appVersion = '1.0.0';

  /// Office support contact — parehong numero na nasa "Contact Us" sheet
  /// (`mobile_scaffold.dart`) at ipinapakita na rin sa "Account Paused"
  /// modal, kaya iisang lugar lang ang babaguhin kapag nagpalit ng number.
  static const String supportPhone = '09755849954';

  /// Office email — ipinapakita sa ilalim ng "Chat" button ng Help Center
  /// (hindi pinipindot ang chat) at pareho rin ng nasa "Contact Us" sheet.
  static const String supportEmail = 'jiretalendingcorp@gmail.com';

  static const int connectTimeoutMs = 30000;
  static const int receiveTimeoutMs = 30000;
  static const int sendTimeoutMs = 30000;

  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  static const int otpLength = 6;
  static const int otpResendSeconds = 60;

  /// Purpose na ipinapadala sa `auth-otp` — inihahambing ito ng server, kaya
  /// hindi magagamit ang OTP ng login sa pag-reset ng MPIN (at kabaliktaran).
  static const String otpPurposeLogin = 'login';
  static const String otpPurposeResetMpin = 'reset_mpin';

  static const int locationUpdateIntervalSeconds = 30;

  static const String termsAcceptedKey = 'terms_accepted';

  /// Full legal name captured right after the lender accepts Terms &
  /// Conditions. Stored per-account (key + '_' + userId) so the Account
  /// Upgrade "Personal Info" step can auto-fill them.
  static const String lenderFirstNameKey = 'lender_first_name';
  static const String lenderMiddleNameKey = 'lender_middle_name';
  static const String lenderLastNameKey = 'lender_last_name';
  static const String lenderSuffixKey = 'lender_suffix';
  static const String lenderEmailKey = 'lender_email';

  /// In-memory flag (NOT persisted): set to true right before a mobile logout
  /// so the login page can show a one-shot "Successfully Logged Out" modal on
  /// arrival. Static — survives the router redirect that follows logout.
  static bool pendingLogoutSuccess = false;

  /// In-memory guard (NOT persisted): while true, the router redirect is held
  /// so the post-logout success modal can stay steady for 2 seconds on the
  /// profile screen before navigating to login.
  static bool suppressLogoutRedirect = false;
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userIdKey = 'user_id';
  static const String userRoleKey = 'user_role';
  static const String sessionStartedAtKey = 'session_started_at';
  static const String lastActivityKey = 'last_activity_at';

  /// Stable, client-generated id for the single-active-session feature. It is
  /// created once per login, survives token refreshes, and is sent with every
  /// request (X-Session-Id header) so the server validates THIS device's
  /// session instead of the JWT session_id claim (which changes whenever
  /// GoTrue mints a new session on sign-in/refresh and would falsely revoke
  /// a healthy session).
  static const String sessionIdKey = 'session_id';
  static const String sessionIdHeaderName = 'X-Session-Id';

  /// Sinusubaybayan ng app kung MAY nakabinbing authenticator (TOTP) challenge
  /// para sa kasalukuyang login — hal. pinatay ang app habang nasa "Verify it's
  /// you" screen.
  ///
  /// HINDI ito patunay ng MFA: hindi ito nagbibigay ng access, pumipigil lang
  /// (nag-uutos na dumaan sa challenge). Ang tanging patunay ay ang `aal: aal2`
  /// claim ng access token, at ang server-side na pagsusuri sa `_shared/mfa.ts`.
  /// Isang simpleng bool lang ito (hindi secret), kaya hindi ito sensitibo sa
  /// storage.
  static const String mfaPendingKey = 'mfa_pending';

  static const String authRefreshPath = 'auth-session?fn=refresh-session';

  /// Session heartbeat: validates + bumps last_seen_at while the app is open.
  static const String authPingPath = 'auth-session?fn=ping';

  /// Idle session timeout para sa rider / lender: 3 minutes of inactivity →
  /// MPIN lock. Any user interaction (tap, scroll, typing) bumps the idle
  /// deadline forward by 3 minutes.
  static const Duration sessionDuration = Duration(minutes: 3);
  static const int sessionDurationMs = 180000;
  static const int sessionDurationSeconds = 180;

  /// Idle session timeout para sa head manager / employee: 15 minutes of
  /// inactivity → AUTO LOGOUT (hard logout, kailangang mag-login muli).
  /// Walang MPIN lock ang staff roles, kaya sa idle expiry ay natatapos
  /// talaga ang session.
  static const Duration staffSessionDuration = Duration(minutes: 15);
  static const int staffSessionDurationMs = 900000;
  static const int staffSessionDurationSeconds = 900;

  /// Ang idle window na applicable sa isang role. Staff (head manager /
  /// employee) = 15 minutes; rider / lender = 3 minutes (lock lang).
  static Duration idleTimeoutForRole(String? role) =>
      role == roleHeadManager || role == roleEmployee
          ? staffSessionDuration
          : sessionDuration;

  /// ABSOLUTE session lifetime: gaano katagal mananatiling wasto ang isang
  /// login bago hilingin muli ang mobile number (OTP). Ang 3-minutong idle
  /// window ng rider / lender ay pag-lock lang ng app (MPIN ang mag-u-unlock) —
  /// HINDI ito nagtatapos ng session. Dito lang (3 buwan) kailangan mag-login
  /// muli ng numero ng rider / lender.
  static const Duration absoluteSessionDuration = Duration(days: 90);

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

  // ── Local preferences (SharedPreferences keys) ────────────────────────
  /// `system` | `light` | `dark`
  static const String prefThemeMode = 'app_theme_mode';

  /// FCM push notifications on/off.
  static const String prefPushNotifications = 'push_notifications_enabled';

  static const String accountUpgradeStatusPending = 'pending';
  static const String accountUpgradeStatusSubmitted = 'submitted';
  static const String accountUpgradeStatusVerified = 'verified';
  static const String accountUpgradeStatusRejected = 'rejected';
}
