// test/ios_platform_config_test.dart
// ─────────────────────────────────────────────────────────────────────────────
// Guards para sa iOS build/config — dapat gumana ang app sa iPhone, hindi
// lang sa Android.
//
// Mga tinatakpan:
//   • Deployment target — iOS 15.5 (ML Kit face detection), hindi 15.0;
//     kapag 15.0 ang Runner, pumapalya ang `pod install`.
//   • ios/Podfile — naka-commit (hindi na umaasa sa auto-generated na 15.0).
//   • Info.plist — LSApplicationQueriesSchemes (tel/sms/mailto/https/http),
//     usage descriptions, remote-notification background mode, at ang
//     deep-link scheme na kapareho ng Android.
//   • Runner.entitlements — aps-environment para sa APNs/FCM.
//   • AppDelegate — notification delegate, Google Maps API key, at plugin
//     registration sa UIScene lifecycle.
//   • firebase_options.dart — ang iOS bundle id ay tugma sa Xcode project.
//
// Static checks lang ito (walang Xcode sa Windows) — hindi kapalit ng tunay
// na `flutter build ios`.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _squash(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

/// Mga `<string>` sa loob ng array na may ibinigay na key sa plist.
List<String> _plistArray(String plist, String key) {
  final match = RegExp(
    '<key>$key</key>\\s*<array>([\\s\\S]*?)</array>',
  ).firstMatch(plist);
  if (match == null) return const [];
  return RegExp(r'<string>([^<]+)</string>')
      .allMatches(match.group(1)!)
      .map((m) => m.group(1)!.trim())
      .toList();
}

void main() {
  final plist = _read('ios/Runner/Info.plist');
  final pbxproj = _read('ios/Runner.xcodeproj/project.pbxproj');

  group('Deployment target — iOS 15.5', () {
    test('Runner.xcodeproj: walang config na mas mababa sa 15.5', () {
      final targets = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);')
          .allMatches(pbxproj)
          .map((m) => double.parse(m.group(1)!))
          .toList();

      expect(targets, isNotEmpty,
          reason: 'dapat may IPHONEOS_DEPLOYMENT_TARGET sa project');
      for (final target in targets) {
        expect(target, greaterThanOrEqualTo(15.5),
            reason:
                'google_mlkit_face_detection ay nangangailangan ng iOS 15.5; '
                'sa 15.0 pumapalya ang pod install');
      }
    });

    test('Podfile: naka-commit at platform :ios, 15.5', () {
      final podfile = _read('ios/Podfile');
      expect(podfile, contains("platform :ios, '15.5'"));
      expect(podfile, contains('flutter_install_all_ios_pods'));
      // Ang bawat pod ay dapat i-align sa parehong minimum.
      expect(podfile, contains("\$iOSVersion = '15.5'"));
      expect(podfile, contains("IPHONEOS_DEPLOYMENT_TARGET'] = \$iOSVersion"));
    });

    test('armv7 ay excluded — hindi sinusuportahan ng ML Kit', () {
      // Kapag naiwan ang armv7 slice, pumapalya ang `flutter build ipa`.
      expect(_read('ios/Podfile'), contains("EXCLUDED_ARCHS[sdk=*]"));
      expect(pbxproj, contains('"EXCLUDED_ARCHS[sdk=*]" = armv7;'),
          reason: 'nasa Runner build settings din dapat, hindi lang sa pods');
    });
  });

  group('Info.plist — iOS runtime', () {
    test('LSApplicationQueriesSchemes: tel/sms/mailto/https/http', () {
      final schemes = _plistArray(plist, 'LSApplicationQueriesSchemes');
      expect(schemes, containsAll(['tel', 'sms', 'mailto', 'https', 'http']),
          reason: 'kung wala, canLaunchUrl ay false sa iOS kaya hindi '
              'gumagana ang Call us, SMS sa borrower at Xendit checkout');
    });

    test('usage descriptions para sa camera, photos, location at Face ID', () {
      for (final key in [
        'NSCameraUsageDescription',
        'NSPhotoLibraryUsageDescription',
        'NSLocationWhenInUseUsageDescription',
        'NSFaceIDUsageDescription',
      ]) {
        expect(plist, contains('<key>$key</key>'),
            reason: 'kailangan ng iOS bago payagan ang permission');
        expect(plist, isNot(contains('<key>$key</key>\n\t<string></string>')));
      }
    });

    test('UIBackgroundModes: remote-notification para sa FCM', () {
      expect(_plistArray(plist, 'UIBackgroundModes'),
          contains('remote-notification'));
    });

    test('deep-link scheme: tugma sa app constants at Android', () {
      final constants = _read('lib/core/constants/app_constants.dart');
      final match =
          RegExp(r"googleOAuthRedirectUri =\s*'([^']+)'").firstMatch(constants);
      expect(match, isNotNull, reason: 'dapat may googleOAuthRedirectUri');
      final scheme = match!.group(1)!.split(':').first;

      expect(_plistArray(plist, 'CFBundleURLSchemes'), contains(scheme),
          reason: 'iOS URL scheme para sa OAuth callback');
      expect(_read('android/app/src/main/AndroidManifest.xml'),
          contains('android:scheme="$scheme"'));
    });
  });

  group('Entitlements at AppDelegate', () {
    test('Runner.entitlements: aps-environment para sa APNs', () {
      final entitlements = _read('ios/Runner/Runner.entitlements');
      expect(entitlements, contains('<key>aps-environment</key>'));
      expect(entitlements, contains('<string>development</string>'));
      expect(pbxproj,
          contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'));
    });

    test('AppDelegate: notification delegate bago ang launch return', () {
      final src = _read('ios/Runner/AppDelegate.swift');
      expect(
          src, contains('UNUserNotificationCenter.current().delegate = self'));
      expect(src, contains('FlutterImplicitEngineDelegate'));
      expect(src, contains('GeneratedPluginRegistrant.register'));
    });

    test('AppDelegate: Google Maps API key (Android-only dati ang mapa)', () {
      final src = _read('ios/Runner/AppDelegate.swift');
      expect(src, contains('GMSServices.provideAPIKey'));
      expect(src, contains('GOOGLE_MAPS_API_KEY'),
          reason: 'parehong env/asset key na ginagamit ng Android build');
      // Parehong pinagmulan ng key sa dalawang platform.
      expect(_read('android/app/build.gradle.kts'),
          contains('GOOGLE_MAPS_API_KEY'));
    });

    test('Info.plist: may URL scheme entry para sa deep link', () {
      expect(_plistArray(plist, 'CFBundleURLSchemes'), isNotEmpty);
      expect(plist, contains('<key>CFBundleURLTypes</key>'));
    });
  });

  group('Firebase iOS config', () {
    test('iosBundleId sa firebase_options ay tugma sa Xcode project', () {
      final options = _read('lib/firebase_options.dart');
      final bundleMatch = RegExp(r"iosBundleId: '([^']+)'").firstMatch(options);
      expect(bundleMatch, isNotNull);

      final projectIds = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
          .allMatches(pbxproj)
          .map((m) => m.group(1)!.trim())
          .where((id) => !id.endsWith('.RunnerTests'))
          .toSet();
      expect(projectIds, contains(bundleMatch!.group(1)));
    });

    test('may iOS FirebaseOptions (hindi web/android lang)', () {
      final options = _squash(_read('lib/firebase_options.dart'));
      expect(options, contains('static const FirebaseOptions ios'));
      expect(options, contains("appId: '1:263204697735:ios:"));
    });
  });
}
