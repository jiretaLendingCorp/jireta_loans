# APK downloads (web)

Ang release APK ay **hindi naka-commit** sa repo. Naka-host ito sa **GitHub
Releases**:

```
https://github.com/jiretaLendingCorp/jireta_loans/releases/latest/download/jireta-loans.apk
```

Ito ang URL na ginagamit ng **Download APK** button sa web login page
(`AppConfig.apkDownloadUrl`).

## Bakit hindi naka-commit

- Ang APK ay **hindi naka-commit** at hindi rin naka-upload sa Storage — nasa
  **GitHub Releases** ito (hanggang 2 GB ang limit ng release asset, kaya kasya
  ang ~141 MB). Ang `*.apk` at `android/key.properties` ay git-ignored.
- Sa **Supabase Storage free plan**, **50 MB** ang maximum na file size (global
  limit na hindi maaaring taasan; 500 GB lang ang kaya sa Pro pataas), kaya
  hindi rin ito ma-upload doon.

## Awtomatiko na ang release (GitHub Actions)

Ang `.github/workflows/android-apk-release.yml` ang bumubuo at nag-a-upload ng
APK. **Tumatakbo ito sa bawat push sa `main`** na may pagbabago sa `lib/**`,
`android/**`, `assets/**`, o `pubspec.yaml` — kaya awtomatikong naka-update ang
asset na binabasa ng `releases/latest/download/jireta-loans.apk`.

Paano ito gumagana:

1. Isang **rolling release** lang ang ginagamit — tag `apk-latest`. Hindi ito
   nadadagdagan ng bagong release kada build; pinapalitan lang
   (`gh release upload --clobber`) ang asset na `jireta-loans.apk`.
   Kaya stable ang download URL forever.
2. `versionCode` = **CI run number**, kaya tumataas ito sa bawat build at
   tinatanggap ng Android ang update sa ibabaw ng lumang install (walang
   "downgrade" error). Ang `versionName` ay galing pa rin sa `pubspec.yaml`.
3. May kasamang `jireta-loans.apk.sha256` na asset para ma-verify ang download.
4. Manual na trigger: **Actions → Android APK (auto release) → Run workflow**.
   May opsyonal na `build_number` input kung gusto mong i-pin ang versionCode.

### Unang setup: GitHub Actions secrets

Kailangan ito bago gumana ang build (isa lang ang beses, sa
**Settings → Secrets and variables → Actions → New repository secret**). Pareho
ang pangalan sa Vercel env vars para madaling kopyahin:

| Secret | Halaga | Required |
| --- | --- | --- |
| `SUPABASE_URL` | `https://YOUR_PROJECT_REF.supabase.co` | ✅ |
| `SUPABASE_ANON_KEY` | Publishable/anon key | ✅ |
| `EDGE_FUNCTIONS_URL` | `https://YOUR_PROJECT_REF.supabase.co/functions/v1` (kung blangko, kukunin mula sa `SUPABASE_URL`) | – |
| `GOOGLE_MAPS_API_KEY` | Maps JS/Android key (manifest placeholder + web) | – |
| `XENDIT_PUBLIC_KEY` | `xendit_public_...` | – |
| `ANDROID_KEYSTORE_BASE64` | base64 ng upload keystore (tingnan sa ibaba) | ✅ |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password | ✅ |
| `ANDROID_KEY_ALIAS` | key alias | ✅ |
| `ANDROID_KEY_PASSWORD` | key password (kung blangko, gagamitin ang keystore password) | – |

### Upload keystore (para gumana ang updates)

Mahalaga ito: kapag **bagong key** ang nag-sign sa bawat build, hindi mai-install
ng users ang bagong APK sa ibabaw ng luma — lalabas ang **"App not installed"**.
Kaya naka-store ang signing key sa secrets.

**Option A — bagong upload keystore (recommended kung wala pang users):**

```bash
# PKCS12 na ang default ng keytool 9+ — huwag nang gumamit ng -storetype JKS.
keytool -genkeypair -v -keystore jireta-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias jireta -storepass 'ILAGAY_ANG_PASSWORD' -keypass 'ILAGAY_ANG_PASSWORD' \
  -dname "CN=Jireta Loans & Credit Corp, O=Jireta Loans, C=PH"

base64 -w0 jireta-upload.jks > jireta-upload.jks.base64   # macOS: base64 -i
```


I-paste ang laman ng `jireta-upload.jks.base64` sa `ANDROID_KEYSTORE_BASE64`, at
`jireta` sa `ANDROID_KEY_ALIAS`. Itago ang `.jks` file kung saan safe — kung
mawala ito, hindi mo na ma-u-update ang naka-install na apps.

⚠️ Ang unang CI build ay may bagong signing key, kaya kailangang **i-uninstall
muna ng existing users** ang lumang debug-signed APK bago ito mai-install.

**Option B — gamitin ang existing debug keystore (para walang i-uninstall ang
users, dahil iyon ang kasalukuyang naka-sign sa naka-install na app):**

```bash
# Windows (Git Bash): $USERPROFILE/.android/debug.keystore (C:\Users\<user>\.android\)
base64 -w0 ~/.android/debug.keystore > debug-keystore.base64
```

Secrets: `ANDROID_KEYSTORE_BASE64` = laman ng file, `ANDROID_KEY_ALIAS` =
`androiddebugkey`, `ANDROID_KEYSTORE_PASSWORD` = `android`,
`ANDROID_KEY_PASSWORD` = `android`. Ang debug keystore ay hindi secure (alam ng
lahat ang password) — pang-testing lang ito.

Sa local na machine, gawin ang parehong file para gumamit ng upload keystore
habang nagbubuild (git-ignored ito):

```properties
# android/key.properties
storeFile=upload-keystore.jks
storePassword=...
keyAlias=jireta
keyPassword=...
```

Ilagay ang keystore sa `android/` o `android/app/` (o gumamit ng absolute path).
Kapag wala ang `android/key.properties`, awtomatikong debug signing ang
gagamitin — hindi masisira ang `flutter run --release`.

### Manu-manong pag-release (fallback)

Kung ayaw mong gamitin ang workflow:

```bash
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk jireta-loans.apk
```

Tapos: GitHub → **Releases** → i-edit ang `apk-latest` (o gumawa ng bagong
release) → i-drag ang `jireta-loans.apk` sa **Attach binaries** → **Publish
release**. Siguraduhing **`jireta-loans.apk`** ang pangalan ng asset, at gamitin
ang parehong keystore na nasa CI secrets.

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
