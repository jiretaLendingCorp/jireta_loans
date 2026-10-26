// test/otp_verify_keyboard_layout_test.dart
//
// Verify OTP (mobile): kapag nakabukas ang keyboard, dating NAGPAPATONG ang
// "Verify OTP" na titulo at ang card. Naka-float kasi ang titulo sa Stack, sa
// labas ng scroll view, habang ang card ay naka-center sa natitirang espasyo —
// kaya umangat ang card papunta sa titulo (lalo na kapag humaba ito dahil sa
// error / lockout na linya). Isang scrollable na column na ngayon ang titulo at
// card, kaya sinisiguro ng tests na ito na hindi sila nagpapatong at hindi rin
// natatakpan ng keyboard ang card.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jireta_loans/presentation/features/auth/screens/otp_verify_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  /// Sadyang 720px ang lapad (mobile pa rin — mas mababa sa 900px na
  /// breakpoint) para hindi sumobra ang mga text sa widget-test font, na
  /// parisukat ang bawat glyph.
  Future<void> pumpOtp(
    WidgetTester tester, {
    required double keyboard,
    bool resetMpin = false,
    Size size = const Size(720, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 24);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OtpVerifyScreen(phone: '09171234567', resetMpin: resetMpin),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  /// Isinasara ang widget tree para ma-dispose ang mga timer ng screen (may
  /// periodic na resend countdown) bago magtapos ang test.
  Future<void> disposeTree(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets('hindi nagpapatong ang titulo at card kapag nakabukas ang keyboard',
      (tester) async {
    await pumpOtp(tester, keyboard: 300);

    // Ang subtitle ay text na nasa titulo lang (wala sa card), kaya
    // hindi ito nakikialam sa "Verify OTP" na nakasulat din sa button.
    final heading = tester.getRect(find.textContaining('We sent a 6-digit code'));
    final firstCardLine = tester.getRect(find.text('Code sent to'));

    expect(heading.bottom, lessThan(firstCardLine.top),
        reason: 'Sumampa ang card sa "Verify OTP" na titulo');

    // Buo pa ring nakikita sa ibabaw ng keyboard ang card.
    final lastCardLine = tester.getRect(find.text("Didn't receive code?"));
    expect(lastCardLine.bottom, lessThan(900 - 300),
        reason: 'Natatakpan ng keyboard ang ibaba ng card');

    // Nakatago ang footer habang nakabukas ang keyboard.
    expect(find.textContaining('Jireta Loans & Credit Corp'), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('hindi nagpapatong ang titulo at card sa reset MPIN flow',
      (tester) async {
    // Mas mataas ang titulo dito (may "Reset MPIN" badge) at mas maliit ang
    // screen — ito ang dating senaryo kung saan talagang nagpapatong sila.
    await pumpOtp(tester,
        keyboard: 300, resetMpin: true, size: const Size(720, 640));

    final heading = tester.getRect(find.textContaining('We sent a 6-digit code'));
    final firstCardLine = tester.getRect(find.text('Code sent to'));

    expect(heading.bottom, lessThan(firstCardLine.top),
        reason: 'Sumampa ang card sa titulo sa reset MPIN flow');

    // Naka-scroll ang natitira — hindi puputulin nang tahimik (may scroll view).
    expect(find.byType(SingleChildScrollView), findsWidgets);

    await disposeTree(tester);
  });

  testWidgets('nakikita ang footer at titulo kapag sarado ang keyboard',
      (tester) async {
    await pumpOtp(tester, keyboard: 0);

    expect(find.textContaining('Jireta Loans & Credit Corp'), findsOneWidget);
    final heading = tester.getRect(find.textContaining('We sent a 6-digit code'));
    final firstCardLine = tester.getRect(find.text('Code sent to'));
    expect(heading.bottom, lessThan(firstCardLine.top));

    await disposeTree(tester);
  });
}
