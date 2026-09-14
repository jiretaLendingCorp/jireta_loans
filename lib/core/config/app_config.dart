// lib/core/config/app_config.dart
class AppConfig {
  AppConfig._();

  static const String companyName = 'Jireta Loans & Credit Corp 1966';
  static const String companyShortName = 'JIRETA';
  static const String appVersion = '1.0.0';
  static const String buildNumber = '1';

  static const double minLoanDisplay = 3000;
  static const double maxLoanDisplay = 500000;

  static const String currency = '₱';
  static const String locale = 'en_PH';
  static const String timezone = 'Asia/Manila';

  // ── Android APK download (web login page) ──────────────────────────────
  // Isang lugar lang ito para mapalitan ang download link kapag may bagong
  // APK release. Puwede rin itong i-override sa build time nang hindi
  // ginagalaw ang code:
  //
  //   flutter build web --dart-define=APK_DOWNLOAD_URL=https://jireta.com/downloads/jireta-loans-1.2.0.apk
  //
  // Ilagay ang APK file sa `web/downloads/` (hal. `web/downloads/
  // jireta-loans.apk`) para maging available ito sa parehong domain ng site.
  static const String apkDownloadUrl = String.fromEnvironment(
    'APK_DOWNLOAD_URL',
    defaultValue: 'https://your-domain.com/downloads/jireta-loans.apk',
  );

  /// Pangalan ng file kapag nag-download ang browser.
  static const String apkFileName = 'jireta-loans.apk';
}
