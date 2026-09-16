# APK downloads (web)

Ang release APK ay **hindi naka-commit** sa repo. Naka-host ito sa **GitHub
Releases**:

```
https://github.com/jiretaLendingCorp/jireta_loans/releases/latest/download/jireta-loans.apk
```

Ito ang URL na ginagamit ng **Download APK** button sa web login page
(`AppConfig.apkDownloadUrl`).

## Bakit hindi naka-commit

- Ang release APK ay ~141 MB — lampas sa **100 MB na file limit ng GitHub**,
  kaya hindi ito ma-push (`GH001: Large files detected`).
- Sa **Supabase Storage free plan**, **50 MB** ang maximum na file size (global
  limit na hindi maaaring taasan; 500 GB lang ang kaya sa Pro pataas), kaya
  hindi rin ito ma-upload doon.
- Naka-`gitignore` na ang `web/downloads/*.apk` para hindi na maulit ito.

## Paano mag-release ng bagong APK

```bash
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk jireta-loans.apk
```

Tapos: GitHub → **Releases** → **Draft a new release** → maglagay ng tag (hal.
`apk-1.0.1`) → i-drag ang `jireta-loans.apk` sa **Attach binaries** → **Publish
release**.

Hindi na kailangang baguhin ang code: ang `releases/latest/download/...` ay
laging tumuturo sa pinakabagong release. Siguraduhing **`jireta-loans.apk`** ang
pangalan ng asset.

Tip: mas maliit ang mada-download ng users (at mas mabilis) kapag
`flutter build apk --release --split-per-abi` — ngunit i-upload pa rin ang
arm64 build bilang `jireta-loans.apk`, o gumawa ng hiwalay na asset at
`APK_DOWNLOAD_URL` para dito.

## Custom na host / CDN

I-set ang `APK_DOWNLOAD_URL` sa Vercel → Project Settings → Environment
Variables (Production). Ipinapasa ito ng `scripts/vercel-build.sh` sa
`--dart-define` — build-time constant ang `String.fromEnvironment`, kaya walang
epekto ang env var kung hindi ito idadaan doon.

```bash
flutter build web --dart-define=APK_DOWNLOAD_URL=https://cdn.example.com/jireta-loans-1.0.1.apk
```

## Ilang paalala

- Hindi na kasama ang `/downloads/*` sa SPA fallback ng `vercel.json`, kaya
  tunay na 404 ang nawawalang APK imbes na `index.html` (HTML) ang maibalik.
- May `HEAD` check ang `downloadFromUrl()` sa
  `lib/presentation/shared/utils/file_downloader_web.dart`: kapag HTML/JSON
  (error page) ang tugon, hindi itutuloy ang download at error toast ang
  lalabas sa login page.
- Siguraduhing `application/vnd.android.package-archive` ang `Content-Type` ng
  APK kapag sariling server/CDN ang gamit.
- Para sa local dev, nandiyan pa rin ang `web/downloads/jireta-loans.apk` (hindi
  ito ipi-push) at kasama ito sa `flutter build web` — kung iyon ang gusto mong
  magamit ng button:
  `flutter build web --dart-define=APK_DOWNLOAD_URL=/downloads/jireta-loans.apk`.
