// test/face_verification_platform_gating_test.dart
//
// FACE VERIFICATION (lender account upgrade) — MOBILE-ONLY GATE
//
// DAHILAN: ang live face verification ay umaasa sa Google ML Kit face detection
// (android + ios lang ang declared platforms sa plugin pubspec) at sa camera
// image stream. Ang `startImageStream` ay
// `UnimplementedError('Streaming is not currently supported on web')` sa
// camera_web — kaya sa web/desktop, dating nag-scan ito nang walang detection at
// WALANG manual capture: dead end na stuck sa "Position your face here".
//
// FIX: `FaceVerificationScreen.isSupported` (Android/iOS lang) at:
//   • unsupported platform → "Available on the mobile app only" notice, at
//     hindi na binubuksan ang camera/ML Kit sa initState
//   • lender submit screen → info dialog, hindi na pinu-push ang screen

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/features/lender/account_upgrade/screens/face_verification_screen.dart';

void main() {
  // NOTE: ang `debugDefaultTargetPlatformOverride` ay kailangang i-reset sa loob
  // ng test body — ang flutter_test ay nagsa-verify ng debug vars bago pa tumakbo
  // ang tearDown.
  testWidgets('desktop → mobile-only notice, walang scanning UI',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(const MaterialApp(home: FaceVerificationScreen()));
    await tester.pump();

    expect(find.text('Available on the mobile app only'), findsOneWidget);
    expect(find.text('Go back'), findsOneWidget);
    // Wala dapat naghihintay na scanning UI na walang capture.
    expect(find.text('Position your face here'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('android → live scanning UI ang naka-render', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(const MaterialApp(home: FaceVerificationScreen()));
    await tester.pump();

    expect(find.text('Available on the mobile app only'), findsNothing);
    expect(find.text('Position your face here'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
