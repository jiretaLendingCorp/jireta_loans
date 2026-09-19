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

  // ── Android APK download (landing page) ──────────────────────────────
  // Naka-host ang APK sa GitHub Releases ng repo (asset name:
  // `jireta-loans.apk`), HINDI sa `web/downloads/`. Dahilan: ang release APK
  // ay ~141 MB — lampas sa 100 MB na file limit ng GitHub at sa 50 MB na file
  // limit ng Supabase Storage free plan — kaya hindi ito ma-commit at hindi
  // rin ma-upload sa Storage. Git-ignored na ang `web/downloads/*.apk`.
  //
  // Ang `releases/latest/download/...` ay laging tumuturo sa pinakabagong
  // release, kaya hindi na kailangang baguhin ang code kapag may bagong APK:
  // i-upload lang ang bagong `jireta-loans.apk` asset sa isang release.
  //
  // Puwede pa ring i-override sa build time nang hindi ginagalaw ang code:
  //
  //   flutter build web --dart-define=APK_DOWNLOAD_URL=https://cdn.example.com/jireta-loans-1.2.0.apk
  static const String apkDownloadUrl = String.fromEnvironment(
    'APK_DOWNLOAD_URL',
    defaultValue:
        'https://github.com/jiretaLendingCorp/jireta_loans/releases/latest/download/jireta-loans.apk',
  );

  /// Pangalan ng file kapag nag-download ang browser.
  static const String apkFileName = 'jireta-loans.apk';
}
