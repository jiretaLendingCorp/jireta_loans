# APK downloads (web)

Ilagay dito ang opisyal na Android build ng Jireta app, halimbawa:

```
web/downloads/jireta-loans.apk
```

Pagkatapos ng `flutter build web`, makokopya ito sa
`build/web/downloads/jireta-loans.apk` at magiging available sa:

```
https://<your-domain>/downloads/jireta-loans.apk
```

Ito ang URL na ginagamit ng **Download APK** button sa web login page.

## Pagpapalit ng link kapag may bagong APK

Isang lugar lang ang kokonfigurahan: `lib/core/config/app_config.dart`
(`AppConfig.apkDownloadUrl` at `AppConfig.apkFileName`).

Puwede ring i-override sa build time nang hindi ginagalaw ang code:

```bash
flutter build web --dart-define=APK_DOWNLOAD_URL=https://jireta.com/downloads/jireta-loans-1.2.0.apk
```

## Note

- Nasa `web/` ang folder na ito kaya kasama ito sa web build; hindi ito
  naka-`gitignore`. Kung ayaw mong i-commit ang malaking `.apk`, i-host na
  lang ito sa CDN/object storage at itakda ang `APK_DOWNLOAD_URL` sa
  `--dart-define`.
- Siguraduhing `application/vnd.android.package-archive` ang
  `Content-Type` ng APK kapag hosted sa server/CDN.
