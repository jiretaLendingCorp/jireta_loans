import Flutter
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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
