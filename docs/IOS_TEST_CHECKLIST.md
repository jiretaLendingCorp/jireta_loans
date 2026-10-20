# iOS test checklist — para talagang gumana sa iPhone

Gabay ito mula build hanggang functional tests. Nasa `docs/IOS_SETUP.md` ang
one-time signing/push/maps setup; ito ang **pagpapatunay** na gumagana nga.

> **Kailangan ng macOS.** Hindi kayang mag-compile ng iOS app sa Windows.
> Gumamit ng Mac, cloud Mac (hal. MacinCloud), o hiram na Mac. Kailangan din
> ng **physical iPhone** para sa camera, Face ID, at tunay na APNs push —
> limitado ang simulator sa mga bahaging ito.

---

## 0. Preflight (5 min)

```bash
cd jireta_loans
flutter --version          # dapat 3.44.x (kapareho ng dev machine)
flutter doctor -v          # walang error sa Xcode / CocoaPods
xcodebuild -version        # 15.3 pataas (requirement ng ML Kit)
pod --version              # may CocoaPods
```

Static config check (pwedeng patakbuhin kahit sa Windows):

```bash
flutter test test/ios_platform_config_test.dart   # 13 tests, dapat lahat pass
```

Sa Mac, may one-command na preflight (pub get → pod install → config tests →
compile):

```bash
bash scripts/ios_preflight.sh
```

Awtomatiko rin itong tumatakbo sa CI tuwing may push na tumatama sa `ios/**`,
`lib/**` o `pubspec.*` — tingnan ang `.github/workflows/ios-build.yml`.

---

## 1. Dependencies at pods

```bash
flutter pub get
cd ios && pod install && cd ..
```

**Pass:** `Pod installation complete!` at may bagong `ios/Podfile.lock`.

**Common fail:** `The platform of the target 'Runner' (iOS 15.0) is not
compatible with 'google_mlkit_face_detection' which requires iOS 15.5` →
hindi na-apply ang 15.5 na config. I-check:

```bash
grep IPHONEOS_DEPLOYMENT_TARGET ios/Runner.xcodeproj/project.pbxproj   # 15.5
grep "platform :ios" ios/Podfile                                       # 15.5
```

Kung stale ang pods: `rm -rf ios/Pods ios/Podfile.lock && (cd ios && pod install)`.

---

## 2. Compile gate (walang signing)

```bash
flutter build ios --debug --no-codesign
```

**Pass:** `Built .../Runner.app`. Dito lumalabas ang anumang Swift/compile
error — kasama ang `import GoogleMaps` at `GMSServices.provideAPIKey()` sa
`AppDelegate.swift`.

---

## 3. Signing at capabilities (Xcode)

```bash
open ios/Runner.xcworkspace     # workspace, HINDI .xcodeproj
```

1. **Runner target → Signing & Capabilities**
   - Team: piliin ang Apple Developer team.
   - Bundle Identifier: `com.example.jiretaLoans` (o sariling id — kung
     papalitan, i-update din ang `iosBundleId` sa `lib/firebase_options.dart`
     at ang Firebase iOS app).
2. **+ Capability → Push Notifications** (may `aps-environment` na sa
   `Runner.entitlements`; kailangan lang i-enable sa App ID/provisioning).
3. **+ Capability → Background Modes → Remote notifications** (nasa
   `Info.plist` na).

**Pass:** walang red signing error; may provisioning profile na may
`aps-environment`.

---

## 4. Apple + Firebase + Maps (one-time, sa console)

- **Apple Developer** → Identifiers → App ID → **Push Notifications** ✓.
- **Firebase Console** → Project settings → Cloud Messaging → i-upload ang
  **APNs Auth Key (.p8)** para sa iOS app.
- **Google Cloud Console** → APIs → i-enable ang **Maps SDK for iOS**; i-restrict
  ang API key sa iOS bundle id.
- Ang `GOOGLE_MAPS_API_KEY` ay dapat nasa isa sa: Xcode scheme environment,
  `Info.plist`, o `assets/env/.env` (binabasa ito ng `AppDelegate`).

---

## 5. Patakbuhin sa iPhone

```bash
flutter devices
flutter run -d <iphone-device-id>
```

Unang run sa device: tiwalaan ang developer cert sa iPhone → Settings →
General → VPN & Device Management.

**Sa console, dapat lumabas:**
- `[FCM] Token acquired`
- `[FCM] Permission after request: authorized` (o `provisional`)
- **WALANG** `[Maps] Walang GOOGLE_MAPS_API_KEY`
- **WALANG** `[core/no-app]` o `apns-token-not-set`

Kung maps lang ang ayaw gumana, patakbuhin mula sa Xcode na may scheme env:

```
Edit Scheme → Run → Arguments → Environment Variables
GOOGLE_MAPS_API_KEY = <key>
```

---

## 6. FCM token registration (database)

Mag-login sa app, tapos sa Supabase SQL Editor:

```sql
select ud.platform, ud.app_version, ud.is_active, ud.created_at
from user_devices ud
where ud.user_id = '<user-id-ng-naka-login>'
order by ud.created_at desc
limit 5;
```

**Pass:** may row na `platform = 'ios'` at `is_active = true`. Kung `android`
ang nakalagay o walang row → hindi tumakbo ang token registration (tingnan
ang FCM logs).

---

## 7. Functional smoke tests

| # | Feature | Gawin | Pass criteria |
| --- | --- | --- | --- |
| 1 | Login + MPIN | Login, patayin ang app, buksan muli | Nananatili ang session; MPIN/keychain gumagana |
| 2 | Permission prompt | Unang bukas pagkatapos ng login | Lalabas ang "Allow notifications" pagkatapos ng unang frame |
| 3 | Foreground push | Mag-send ng notification sa naka-login na user (HM/Employee → `notifications-send`, o tunay na loan flow) | **Isang** banner lang (walang doble), may tunog |
| 4 | Background push | I-background ang app, magpadala ng push | Lalabas sa Notification Center; tama ang title/body |
| 5 | Tap → deep link | I-tap ang push habang background | Bubukas ang tamang screen (`reference_id`) |
| 6 | Cold-start push | Force-quit ang app, magpadala ng push, i-tap | Bubukas ang app at dumeretso sa tamang screen |
| 7 | Maps | Rider login → Live Tracking (`/rider/live-tracking`) | May map tiles at rider marker — hindi blangko/abo |
| 8 | Call | Account Paused modal → "Call us", o Contact Us | Bubukas ang iOS dialer na may `09755849954` |
| 9 | SMS | Rider → borrower info → SMS icon | Bubukas ang Messages na may tamang numero |
| 10 | Xendit checkout | Lender → pay via GCash | Bubukas ang checkout sa Safari (hindi tahimik na fail) |
| 11 | Face verification | Lender account upgrade → Face Verification (**physical device**) | Camera preview, oval guide, detection, capture, success |
| 12 | Photo/camera upload | ID at document upload | Lumalabas ang iOS permission dialogs; naka-upload |
| 13 | Location | Rider mag-share ng live location | Permission prompt, gumagalaw ang marker habang bukas ang app |
| 14 | Biometrics | Loan submit o COD payment | Face ID / passcode prompt, tumutuloy pagkatapos |
| 15 | Deep link | `xcrun simctl openurl booted 'com.jireta.loans://login-callback?code=test'` (simulator) | Bubukas ang app sa callback handling |
| 16 | Report export | I-export ang PDF/Excel | Bubukas ang iOS share/preview sheet |

### Paano magpadala ng test push

HM/Employee account → `POST /functions/v1/notifications-send`:

```json
{
  "user_id": "<lender-or-rider-user-id>",
  "title": "Test iOS",
  "message": "Foreground push test",
  "type": "<valid notification type code>"
}
```

Kunin ang valid type: `select code from notification_types;`

---

## 8. Release build at TestFlight

```bash
flutter build ipa --release
open build/ios/archive/Runner.xcarchive   # Organizer → Distribute App
```

I-install sa TestFlight at ulitin ang #3–#6 (push) at #7, #11. Dito
gumagana ang **production APNs** — dapat walang `apns-token-not-set` sa
release/TestFlight build.

---

## 9. Clean-build regression

Para masigurong walang naka-depende sa stale na pods:

```bash
flutter clean
flutter pub get
rm -rf ios/Pods ios/Podfile.lock
(cd ios && pod install)
flutter build ios --release --no-codesign
flutter test test/ios_platform_config_test.dart
```

---

## 10. Troubleshooting quick table

| Sintomas | Malamang dahilan | Fix |
| --- | --- | --- |
| `pod install` platform error (15.0 vs 15.5) | Hindi naka-15.5 | `Podfile` + `project.pbxproj` = 15.5 |
| `Runner` requires provisioning profile with `aps-environment` | Push capability wala sa App ID | Enable sa portal, regenerate profile |
| `apns-token-not-set` | Entitlement/APNs key, o simulator | Physical device; APNs `.p8` sa Firebase |
| Blangko ang mapa | Walang Maps key | `GOOGLE_MAPS_API_KEY` sa env/Info.plist/`.env`; enable Maps SDK for iOS |
| `initWithContentsOfFile ... GoogleService-Info.plist` | May lumang native init | App uses explicit `FirebaseOptions` — huwag mag-`FirebaseApp.configure()` nang walang plist |
| Call/SMS/checkout tahimik | Scheme wala sa `LSApplicationQueriesSchemes` | Nasa `Info.plist` na: tel, sms, mailto, https, http |
| Doble ang notification sa foreground | Naka-doble ang display path | Dapat `return` sa iOS sa `_handleForegroundMessage` |
| Push tap hindi nag-navigate sa cold start | `attachRouter` bago ang router | I-check ang `app.dart` attach + `getInitialMessage` |
