import Flutter
import GoogleMaps
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // ── FCM / push setup (iOS) ─────────────────────────────────────────────
    // Kailangang NAKA-SET na ang UNUserNotificationCenter.delegate bago
    // bumalik ang application(_:didFinishLaunchingWithOptions:) — requirement
    // ito ng Apple. Sa UIScene lifecycle (default na sa Flutter 3.41+),
    // PAGKATAPOS ng launch events nairerehistro ang Flutter plugins, kaya
    // hindi ito kayang gawin ng firebase_messaging o ng
    // flutter_local_notifications mismo: hinihintay nila ang
    // UIApplicationDidFinishLaunchingNotification, na hindi na dumarating
    // kapag UIScene ang app. Bunga noon, hindi tumatakbo ang native FCM
    // setup, walang APNs/FCM token, at walang push sa iOS.
    //
    // Ang FlutterAppDelegate ay conform sa UNUserNotificationCenterDelegate
    // (sa pamamagitan ng FlutterAppLifeCycleProvider) at ipinapasa nito ang
    // notification callbacks sa lahat ng naka-register na plugins (FCM at
    // local notifications). Kapag nakita ng firebase_messaging ang delegate
    // na ito, hindi niya na ito pinapalitan.
    UNUserNotificationCenter.current().delegate = self

    // ── Google Maps SDK (iOS) ──────────────────────────────────────────────
    // Sa Android, ang API key ay pumapasok sa AndroidManifest placeholder
    // (`MAPS_API_KEY`, mula sa GOOGLE_MAPS_API_KEY env o assets/env/.env —
    // tingnan ang android/app/build.gradle.kts). Sa iOS, WALANG manifest
    // placeholder: kailangang tawagin ng native code ang
    // GMSServices.provideAPIKey() BAGO mabuo ang kahit anong map view. Kapag
    // hindi ito natawag, blangko ang mapa at "Google Maps SDK for iOS must be
    // initialized" ang error sa log — kaya dati Android-only ang gumaganang
    // mapa.
    Self.configureGoogleMaps()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - Google Maps

  /// Sinisimulan ang Google Maps SDK gamit ang parehong key na ginagamit ng
  /// Android. Pagkakasunod-sunod ng pinagkukunan:
  ///   1. `GOOGLE_MAPS_API_KEY` environment variable (Xcode scheme / CI)
  ///   2. `GOOGLE_MAPS_API_KEY` sa Info.plist
  ///   3. `assets/env/.env` na naka-bundle sa app (kaparehong file na
  ///      binabasa ng android/app/build.gradle.kts at ng flutter_dotenv)
  private static func configureGoogleMaps() {
    guard let key = googleMapsAPIKey(), !key.isEmpty else {
      NSLog("[Maps] Walang GOOGLE_MAPS_API_KEY — hindi naka-initialize ang Google Maps SDK (blangko ang mapa sa iOS).")
      return
    }
    GMSServices.provideAPIKey(key)
  }

  private static func googleMapsAPIKey() -> String? {
    if let envKey = ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"],
      !envKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return envKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Kapag hindi na-substitute ang build setting, `$(GOOGLE_MAPS_API_KEY)`
    // ang laman — ituring na wala, huwag ipasa sa SDK.
    if let plistKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String {
      let trimmed = plistKey.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty && !trimmed.hasPrefix("$(") {
        return trimmed
      }
    }

    return googleMapsAPIKeyFromBundledEnv()
  }

  /// Binabasa ang `GOOGLE_MAPS_API_KEY=` mula sa Flutter asset na `.env`
  /// (`Runner.app/Frameworks/App.framework/flutter_assets/assets/env/.env`).
  private static func googleMapsAPIKeyFromBundledEnv() -> String? {
    guard
      let frameworksURL = Bundle.main.url(forResource: "Frameworks", withExtension: nil),
      let contents = try? String(
        contentsOf: frameworksURL.appendingPathComponent("App.framework/flutter_assets/assets/env/.env"),
        encoding: .utf8
      )
    else {
      return nil
    }

    for line in contents.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed.hasPrefix("GOOGLE_MAPS_API_KEY=") else { continue }
      // `dropFirst` returns a Substring — kailangang gawing String bago
      // tawagin ang Foundation trimming/String? return value.
      let value = String(trimmed.dropFirst("GOOGLE_MAPS_API_KEY=".count))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? nil : value
    }
    return nil
  }
}
