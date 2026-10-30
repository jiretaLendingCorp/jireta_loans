# iOS setup — Jireta Loans

Naka-commit na ang lahat ng kailangan ng app para tumakbo sa iPhone/iPad.
Ang mga natitira ay **one-time, per-developer/per-Apple-account** na hakbang
(signing, capabilities, APNs key) na hindi maaaring i-commit sa repo.

Para sa step-by-step na pag-test pagkatapos ng setup (build gate, push,
maps, face verification, TestFlight), tingnan ang
[`docs/IOS_TEST_CHECKLIST.md`](IOS_TEST_CHECKLIST.md).

May tatlong automated na build check:

- **CI:** `.github/workflows/ios-build.yml` — macOS runner, `pod install` +
  `flutter build ios --no-codesign` sa bawat push na tumatama sa `ios/**`,
  `lib/**` o `pubspec.*`. Ito ang nagpapatunay na nagko-compile ang iOS build
  kahit walang Mac sa dev machine.
- **Codemagic:** `codemagic.yaml` — `ios-compile` (parehong no-signing build),
  `ios-sideload-ipa` (unsigned IPA para sa libreng install sa iPhone) at
  `ios-testflight` (signed IPA). Tingnan ang
  [Codemagic](#codemagic-ios-build-mula-sa-windows) sa ibaba.
- **Local:** `bash scripts/ios_preflight.sh` — parehong hakbang sa sariling Mac.

### Codemagic (iOS build mula sa Windows)

Nasa root ang `codemagic.yaml`. Kapag nakita ito ng Codemagic, **ito ang
ginagamit at binabalewala ang "Default Workflow"** sa UI.

| Workflow | Kailangan | Ginagawa |
| --- | --- | --- |
| `ios-compile` | wala — gumagana kahit free Apple ID | `flutter build ios --release --no-codesign`, `pod install`, config guard tests |
| `ios-sideload-ipa` | free Apple ID + Windows laptop (Sideloadly) | unsigned IPA (`Payload/Runner.app`) na ipi-pirma at i-install sa iPhone |
| `ios-testflight` | **bayad na Apple Developer Program** (App Manager API key), App ID at app record sa App Store Connect | signed IPA + upload sa TestFlight |

Ang error na
`Building a deployable iOS app requires a selected Development Team with a
Provisioning Profile` ay **hindi bug sa app**: humihingi lang ng signing ang
device build (`flutter build ios` / `flutter build ipa`).

Sa free Apple ID, **hindi kayang mag-sign ang Codemagic** — ang automatic
signing nito ay dumadaan sa App Store Connect API key, at wala iyon sa
free/personal team (walang developer-portal access, walang distribution
certificate). Wala ring "Apple ID login" ang Codemagic. Kaya hindi ito
maayos sa CI; ang libreng daan ay `ios-sideload-ipa` + Sideloadly sa laptop
(sa ibaba).

### Libreng pag-install sa iPhone (free Apple ID + Sideloadly)

Ito ang **development build sa sariling iPhone**, hindi TestFlight. 7 araw
ang bisa ng cert ng free Apple ID, at hindi nito kayang magdala ng push
notifications.

1. **Codemagic** → App settings → Environment variables → **group na
   `jireta_env`** (kailangang eksaktong ganoon ang pangalan — ito ang
   nakalista sa `groups` ng `codemagic.yaml`): `SUPABASE_URL`,
   `SUPABASE_ANON_KEY`, `GOOGLE_MAPS_API_KEY`, `XENDIT_PUBLIC_KEY`. Ang mga
   value ay nasa lokal na `assets/env/.env`. I-save, tapos gumawa ng
   **bagong** build — hindi na-a-apply sa kasalukuyang build ang bagong
   variable. Ang `ios-sideload-ipa` ay **hihinto** kapag kulang ang dalawang
   Supabase values — sinasadya ito para hindi ka mag-install ng placeholder
   build.

   Kapag lumabas ang `SUPABASE_URL is required for a device-testing build`,
   ibig sabihin ay wala sa build machine ang variable: tingnan na umiiral ang
   `jireta_env` group, may laman itong `SUPABASE_URL`, at naka-save.
2. **Start new build** → piliin ang
   `iOS unsigned IPA (free Apple ID, sideload sa iPhone)` → hintayin ang
   `jireta-loans-unsigned.ipa` sa Artifacts.
3. **Windows:** i-install ang **Apple Devices** (Microsoft Store) para sa
   drivers — huwag ang iTunes mula sa Store, kulang ito sa Apple Mobile
   Device Support. I-download din ang **Sideloadly** (sideloadly.io).
4. Isaksak ang iPhone → **Trust This Computer** sa iPhone.
5. Buksan ang Sideloadly → i-drag ang IPA → ilagay ang Apple ID mo →
   **Start**. Unang beses lang hihingi ng 2FA code mula sa iPhone.
6. Kapag sinabing taken ang bundle id, palitan ito sa Sideloadly (hal.
   `com.kyl.jiretaLoans`). Tandaan: nakatali sa bundle id ang API key
   restriction ng Firebase iOS app, kaya kailangang i-update din iyon sa
   Firebase/Google Cloud kapag pinalitan.
7. Sa iPhone: **Settings → General → VPN & Device Management** → tiwalaan
   ang `Apple Development: <email mo>`.
8. iOS 16 pataas: **Settings → Privacy & Security → Developer Mode → On**,
   tapos i-restart. Kung wala ito, hindi bubukas ang sideloaded app.
9. Buksan ang app. Pagkalipas ng 7 araw, i-run ulit ang Sideloadly (may
   auto-refresh option) para ma-renew ang cert.

Mga limitasyon ng free account: **3 sideloaded apps** lang sa isang device,
10 App IDs kada 7 araw, at walang push notifications (`aps-environment` ay
paid-only capability). Ang build na ito ay unsigned sa Codemagic — walang
entitlements, kaya hindi sumasablay ang re-signing. Personal testing lang
ito; hindi ito para sa distribution.

Kapag naka-enroll na sa paid program, isang beses lang ang setup para sa
`ios-testflight`:

1. **App Store Connect** → Users and Access → Integrations → App Store Connect
   API → gumawa ng key (App Manager), i-download ang `.p8`, itala ang Issuer ID
   at Key ID.
2. **Codemagic** → Team settings → Integrations → Developer Portal → **Add
   key**, pangalang `jireta_appstore` (kailangang tugma sa
   `integrations.app_store_connect` sa `codemagic.yaml`).
3. **Apple Developer** → Identifiers → gumawa ng App ID para sa `BUNDLE_ID`
   (may Push Notifications), pagkatapos ay gumawa ng app record sa App Store
   Connect.
4. **Codemagic** → App settings → Environment variables → group na
   `jireta_env` (eksaktong pangalan, tugma sa `groups` ng `codemagic.yaml`):
   `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_MAPS_API_KEY`,
   `XENDIT_PUBLIC_KEY` (ito ang isinusulat sa `assets/env/.env`; ang
   `ios-compile` ay may placeholder kapag wala) at `CERTIFICATE_PRIVATE_KEY`
   (secret) para makagawa ng distribution certificate. Kung wala pang
   certificate private key sa Mac, puwedeng gumawa sa Git Bash at i-paste
   ang buong file:

   ```bash
   ssh-keygen -t rsa -b 2048 -m PEM -f ios_distribution_private_key -q -N ""
   cat ios_distribution_private_key   # paste as CERTIFICATE_PRIVATE_KEY
   ```

5. Patakbuhin ang `ios-testflight`.

Kung papalitan ang bundle id (hal. dahil taken na ang `com.example.*` sa Apple),
baguhin ang `PRODUCT_BUNDLE_IDENTIFIER` sa Xcode at ang `BUNDLE_ID` sa
`codemagic.yaml`, tapos i-update ang `iosBundleId` sa
`lib/firebase_options.dart` at ang Firebase iOS app.

## Ano ang naka-commit na

| Bahagi | File | Tala |
| --- | --- | --- |
| Minimum iOS | `ios/Podfile`, `ios/Runner.xcodeproj` | **iOS 15.5** — requirement ng `google_mlkit_face_detection` (15.5) at Firebase Apple SDK 12 (15.0). Huwag ibaba sa 15.0: pumapalya ang `pod install`. Naka-exclude din ang `armv7` (32-bit) dahil hindi ito sinusuportahan ng ML Kit. |
| Push / APNs | `ios/Runner/AppDelegate.swift`, `ios/Runner/Runner.entitlements`, `ios/Runner/Info.plist` | Naka-set ang `UNUserNotificationCenter.delegate` bago mag-launch, may `aps-environment`, at `remote-notification` background mode. |
| Deep link (Google OAuth) | `ios/Runner/Info.plist` | URL scheme `com.jireta.loans` — tugma sa `AppConstants.googleOAuthRedirectUri` at sa Android intent-filter. |
| Panlabas na apps | `ios/Runner/Info.plist` | `LSApplicationQueriesSchemes`: `tel`, `sms`, `mailto`, `https`, `http`. Kung wala ito, hindi gumagana sa iOS ang "Call us", SMS sa borrower at Xendit checkout. |
| Google Maps | `ios/Runner/AppDelegate.swift` | `GMSServices.provideAPIKey()` — hinahanap ang key sa `GOOGLE_MAPS_API_KEY` env, Info.plist, o `assets/env/.env` (parehong source ng Android build). |
| Permissions | `ios/Runner/Info.plist` | Camera, photo library, microphone, location, Face ID. |
| Firebase config | `lib/firebase_options.dart` | Explicit na `FirebaseOptions` (kasama ang iOS app), kaya **hindi** kailangan ng `GoogleService-Info.plist`. |
| Gating sa code | `face_verification_screen.dart`, `fcm_service.dart` | Parehong Android **at** iOS ang tahasang sinusuportahan; ang ibang platform ay may malinaw na fallback. |

## Mga hakbang sa macOS (isang beses lang)

1. **Dependencies at pods**

   ```bash
   flutter pub get
   cd ios && pod install && cd ..
   ```

   Buksan ang `ios/Runner.xcworkspace` (**hindi** ang `.xcodeproj`) kapag
   gagamit ng Xcode.

2. **Signing**

   Xcode → Runner target → *Signing & Capabilities* → piliin ang Team.
   Ang bundle id ay `com.jiretalendingcorp.app` (nasa `Runner.xcodeproj` at
   `lib/firebase_options.dart`). Kung palitan ito ng tunay na reverse-DNS id:

   - baguhin ang `PRODUCT_BUNDLE_IDENTIFIER` sa Xcode,
   - i-update ang `iosBundleId` sa `lib/firebase_options.dart`,
   - i-register ang bagong bundle id sa Firebase (iOS app) at Apple Developer
     portal (App ID na may Push Notifications capability).

3. **Push Notifications**

   - Xcode → Runner target → *Signing & Capabilities* → **+ Push
     Notifications** (nababasa na ang `aps-environment` entitlement).
   - Sa Apple Developer portal: App ID → **Push Notifications** capability.
   - Firebase Console → Project Settings → Cloud Messaging → i-upload ang APNs
     authentication key (`.p8`).
   - Background Modes → *Remote notifications* ay nasa `Info.plist` na.

4. **Google Maps key**

   Ang `GOOGLE_MAPS_API_KEY` ay kailangang naroon sa isa sa mga ito:
   environment variable ng build, Info.plist, o `assets/env/.env`. Sa Google
   Cloud Console, i-restrict ang key sa iOS bundle id (at sa Android app
   separately para sa Android).

5. **Patakbuhin**

   ```bash
   flutter run -d <iphone-device-id>          # debug sa device/simulator
   flutter build ios --release                # release
   flutter build ipa --release                # TestFlight / App Store
   ```

   Ang `flutter build ipa` ay nagre-require ng valid signing profile. Puwede
   ring `flutter build ios --no-codesign` sa CI para ma-verify na nagko-compile
   (macOS runner lang).

## Mahalagang tala

- **Hindi kayang mag-build ng iOS sa Windows.** Kailangan ng macOS + Xcode —
  sariling Mac, o macOS runner ng Codemagic/GitHub Actions (tingnan sa itaas).
  Ang mga test na `test/ios_platform_config_test.dart` ay static checks lang —
  binabantayan nito ang config drift, hindi kapalit ng tunay na build.
- Huwag ibaba ang deployment target sa 15.0. Ang ML Kit face detection pod ay
  `s.platform = :ios, '15.5'`; kapag mas mababa ang Runner, pumapalya ang
  `pod install` bago pa man mag-compile.
- Kung magdadagdag ng bagong Firebase app para sa iOS, patakbuhin ang
  `flutterfire configure` at i-commit ang na-update na `lib/firebase_options.dart`.
