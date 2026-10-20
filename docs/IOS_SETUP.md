# iOS setup — Jireta Loans

Naka-commit na ang lahat ng kailangan ng app para tumakbo sa iPhone/iPad.
Ang mga natitira ay **one-time, per-developer/per-Apple-account** na hakbang
(signing, capabilities, APNs key) na hindi maaaring i-commit sa repo.

Para sa step-by-step na pag-test pagkatapos ng setup (build gate, push,
maps, face verification, TestFlight), tingnan ang
[`docs/IOS_TEST_CHECKLIST.md`](IOS_TEST_CHECKLIST.md).

May dalawang automated na build check:

- **CI:** `.github/workflows/ios-build.yml` — macOS runner, `pod install` +
  `flutter build ios --no-codesign` sa bawat push na tumatama sa `ios/**`,
  `lib/**` o `pubspec.*`. Ito ang nagpapatunay na nagko-compile ang iOS build
  kahit walang Mac sa dev machine.
- **Local:** `bash scripts/ios_preflight.sh` — parehong hakbang sa sariling Mac.

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
   Ang bundle id ay `com.example.jiretaLoans` (nasa `Runner.xcodeproj` at
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

- **Hindi kayang mag-build ng iOS sa Windows.** Kailangan ng macOS + Xcode.
  Ang mga test na `test/ios_platform_config_test.dart` ay static checks lang —
  binabantayan nito ang config drift, hindi kapalit ng tunay na build.
- Huwag ibaba ang deployment target sa 15.0. Ang ML Kit face detection pod ay
  `s.platform = :ios, '15.5'`; kapag mas mababa ang Runner, pumapalya ang
  `pod install` bago pa man mag-compile.
- Kung magdadagdag ng bagong Firebase app para sa iOS, patakbuhin ang
  `flutterfire configure` at i-commit ang na-update na `lib/firebase_options.dart`.
