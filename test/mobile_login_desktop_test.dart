// test/mobile_login_desktop_test.dart
//
// Desktop layout ng mobile login page (`/mobile-login`).
//
// Sa desktop, ang login form ay dating buong-lapad na mobile card — nakaunat
// hanggang sa gilid ng browser. Ngayon, naka-center ito sa isang makitid na
// column (≤480px, kapareho ng desktop auth surfaces ng app) sa malawak na
// panel. Sa mobile, hindi nagbabago: buong lapad pa rin ang card.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jireta_loans/core/security/mpin_login_gate.dart';
import 'package:jireta_loans/presentation/features/auth/screens/mobile_login_screen.dart';
import 'package:jireta_loans/presentation/shared/providers/connectivity_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpLogin(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityProvider.overrideWith((ref) => Stream<bool>.value(true)),
        ],
        // `handoff` — alam na agad kung OTP form o MPIN ang lalabas, kaya
        // hindi na nagbabasa ng secure storage sa unang frame.
        child: const MaterialApp(
          home: MobileLoginScreen(
            handoff: MpinLoginChoice(showMpin: false, phone: '09171234567'),
          ),
        ),
      ),
    );
    await tester.pump();
    // Tapusin ang fade/slide entrance (700ms) ng form.
    await tester.pump(const Duration(seconds: 1));
  }

  /// Isinasara ang widget tree para ma-dispose ang mga provider (may periodic
  /// na timer ang auth notifier) bago magtapos ang test.
  Future<void> disposeTree(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets('desktop (1280px): naka-center na makitid na login card',
      (tester) async {
    await pumpLogin(tester, 1280);

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Mobile Number'), findsOneWidget);
    expect(find.text('Send OTP'), findsOneWidget);

    final fieldWidth = tester.getSize(find.byType(TextFormField)).width;
    final fieldCenter = tester.getCenter(find.byType(TextFormField));
    // Card = ≤480 (may 20px na padding sa gilid) — hindi nakaunat sa buong
    // 1280px na browser.
    expect(fieldWidth, lessThan(440),
        reason: 'Nakaunat pa rin ang form sa buong lapad ng desktop');
    expect(fieldCenter.dx, closeTo(640, 3),
        reason: 'Hindi naka-center ang login card sa desktop');

    await disposeTree(tester);
  });

  // Sadyang HINDI phone width (390) ang ginamit dito: sa widget test font ng
  // Flutter, parisukat ang bawat glyph, kaya ang 11px na copyright row sa
  // footer ay sumusobra sa 350px na lapad kahit wala namang totoong overflow.
  // Ang mahalagang tsek dito ay ang gawi SA ILALIM ng desktop breakpoint.
  testWidgets('below breakpoint (720px): buong lapad pa rin ang login card',
      (tester) async {
    await pumpLogin(tester, 720);

    expect(find.text('Login'), findsOneWidget);
    final fieldWidth = tester.getSize(find.byType(TextFormField)).width;
    final fieldCenter = tester.getCenter(find.byType(TextFormField));
    // Buong lapad (may 20px padding sa gilid) — hindi naka-cap sa 480px.
    expect(fieldWidth, greaterThan(600));
    expect(fieldCenter.dx, closeTo(360, 3));

    await disposeTree(tester);
  });
}
