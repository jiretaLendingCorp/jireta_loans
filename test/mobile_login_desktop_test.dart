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

import 'package:jireta_loans/core/constants/app_constants.dart';
import 'package:jireta_loans/core/security/mpin_login_gate.dart';
import 'package:jireta_loans/presentation/features/auth/screens/mobile_login_screen.dart';
import 'package:jireta_loans/presentation/shared/providers/connectivity_provider.dart';
import 'package:jireta_loans/presentation/shared/widgets/security/mpin_keypad.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpLogin(
    WidgetTester tester,
    double width, {
    bool showMpin = false,
    double height = 800,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityProvider.overrideWith((ref) => Stream<bool>.value(true)),
        ],
        // `handoff` — alam na agad kung OTP form o MPIN ang lalabas, kaya
        // hindi na nagbabasa ng secure storage sa unang frame.
        child: MaterialApp(
          home: MobileLoginScreen(
            handoff: MpinLoginChoice(
              showMpin: showMpin,
              phone: '09171234567',
            ),
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

    expect(find.text('Login as'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Or'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Send OTP'), findsOneWidget);
    // Nakatago muna ang Google sign-in sa ilalim ng Send OTP.
    expect(find.text('or continue with'), findsNothing);
    expect(find.text('Continue with Google'), findsNothing);

    final fieldWidth =
        tester.getSize(find.byKey(const Key('loginPhoneField'))).width;
    final fieldCenter =
        tester.getCenter(find.byKey(const Key('loginPhoneField')));
    // Card = ≤480 (may 20px na padding sa gilid) — hindi nakaunat sa buong
    // 1280px na browser.
    expect(fieldWidth, lessThan(440),
        reason: 'Nakaunat pa rin ang form sa buong lapad ng desktop');
    expect(fieldCenter.dx, closeTo(640, 3),
        reason: 'Hindi naka-center ang login card sa desktop');

    // Walang overlap: nasa ILALIM ng brand header ang simula ng card.
    final brand = tester.getRect(find.text('Jireta Loans'));
    final heading = tester.getRect(find.text('Login as'));
    expect(heading.top, greaterThan(brand.bottom),
        reason: 'Naka-overlap ang brand header at ang login card');

    await disposeTree(tester);
  });

  // Sadyang HINDI phone width (390) ang ginamit dito: sa widget test font ng
  // Flutter, parisukat ang bawat glyph, kaya ang 11px na copyright row sa
  // footer ay sumusobra sa 350px na lapad kahit wala namang totoong overflow.
  // Ang mahalagang tsek dito ay ang gawi SA ILALIM ng desktop breakpoint.
  testWidgets('below breakpoint (720px): buong lapad pa rin ang login card',
      (tester) async {
    await pumpLogin(tester, 720);

    expect(find.text('Login as'), findsOneWidget);
    final fieldWidth =
        tester.getSize(find.byKey(const Key('loginPhoneField'))).width;
    final fieldCenter =
        tester.getCenter(find.byKey(const Key('loginPhoneField')));
    // Buong lapad (may 20px padding sa gilid) — hindi naka-cap sa 480px.
    expect(fieldWidth, greaterThan(600));
    expect(fieldCenter.dx, closeTo(360, 3));

    await disposeTree(tester);
  });

  // Dalawang field ngayon: "Phone number" at "Email" (may "Or" sa gitna). Ang
  // email ang nagpapa-enable ng Send OTP, at isa lang ang aktibong identifier —
  // kapag may nilagay sa isang field, nabubura ang laman ng isa pa.
  testWidgets('email (Gmail) sa Email field: naka-enable ang Send OTP',
      (tester) async {
    await pumpLogin(tester, 720);

    await tester.enterText(
        find.byKey(const Key('loginEmailField')), '  Juan@Gmail.com ');
    await tester.pump();

    final cta = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Send OTP'));
    expect(cta.onPressed, isNotNull,
        reason: 'Hindi naka-enable ang Send OTP para sa email');

    // Iisa lang ang aktibong identifier: nabubura ang email kapag may
    // nilagay na numero sa phone field.
    await tester.enterText(
        find.byKey(const Key('loginPhoneField')), '9171234567');
    await tester.pump();
    final email =
        tester.widget<TextFormField>(find.byKey(const Key('loginEmailField')));
    expect(email.controller?.text, isEmpty,
        reason: 'Hindi nabura ang email nang may nilagay na numero');

    await disposeTree(tester);
  });

  testWidgets('mobile number sa Phone number field: naka-format at naka-enable',
      (tester) async {
    await pumpLogin(tester, 720);

    await tester.enterText(
        find.byKey(const Key('loginPhoneField')), '9171234567');
    await tester.pump();

    expect(find.text('917 123 4567'), findsOneWidget);
    final cta = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Send OTP'));
    expect(cta.onPressed, isNotNull);

    await disposeTree(tester);
  });

  // Sa laptop na ~687px ang taas ng browser, dating putol ang keypad (1–6 lang
  // ang kita). Itinaas ito para buo ang 1–9 at 0 sa unang view.
  testWidgets('desktop (1366x687): buo ang number keypad sa unang view',
      (tester) async {
    await pumpLogin(tester, 1366, showMpin: true, height: 687);

    expect(find.text('Enter MPIN'), findsOneWidget);
    final keypad = tester.getRect(find.byType(MpinKeypadField));
    expect(keypad.bottom, lessThanOrEqualTo(687),
        reason: 'Nasa ibaba pa rin ng viewport ang ilang numero');
    for (final digit in const [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '0',
    ]) {
      expect(find.text(digit), findsOneWidget);
    }

    await disposeTree(tester);
  });

  // Help Center ng mobile login: dating nakaunat sa buong browser at walang
  // paraan para makipag-chat. Ngayon naka-center/capped ang content sa
  // desktop at may Chat + email + numero sa dulo ng FAQ.
  testWidgets(
      'desktop (1280px) Help Center: capped ang lapad at pantay ang '
      'Chat/email/numero', (tester) async {
    await pumpLogin(tester, 1280);

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Help Center'));
    await tester.pumpAndSettle();

    expect(find.text('Frequently Asked Questions'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);

    // Hindi dapat mapindot ang "Chat" — nasa ilalim nito ang email at numero
    // ng Jireta bilang tunay na paraan ng pakikipag-ugnayan.
    final chat = tester.widget<InkWell>(
      find
          .ancestor(of: find.text('Chat'), matching: find.byType(InkWell))
          .first,
    );
    expect(chat.onTap, isNull, reason: 'Pinipindot pa rin ang Chat');
    expect(find.text(AppConstants.supportEmail), findsOneWidget);
    expect(find.text(AppConstants.supportPhone), findsOneWidget);

    // Pantay ang tatlong linya: parehong x ang icon column at pareho rin ang
    // x ng text column (Chat, email, numero).
    final chatIconX =
        tester.getTopLeft(find.byIcon(Icons.chat_bubble_outline_rounded)).dx;
    final mailIconX =
        tester.getTopLeft(find.byIcon(Icons.mail_outline_rounded)).dx;
    final phoneIconX = tester.getTopLeft(find.byIcon(Icons.phone_outlined)).dx;
    expect(mailIconX, closeTo(chatIconX, 0.5));
    expect(phoneIconX, closeTo(chatIconX, 0.5));

    final chatTextX = tester.getTopLeft(find.text('Chat')).dx;
    final mailTextX =
        tester.getTopLeft(find.text(AppConstants.supportEmail)).dx;
    final phoneTextX =
        tester.getTopLeft(find.text(AppConstants.supportPhone)).dx;
    expect(mailTextX, closeTo(chatTextX, 0.5));
    expect(phoneTextX, closeTo(chatTextX, 0.5));

    // Mapipindot ang email at numero — direktang bubukas ang mail app / dialer.
    for (final label in [
      AppConstants.supportEmail,
      AppConstants.supportPhone,
    ]) {
      final ink = tester.widget<InkWell>(
        find
            .ancestor(of: find.text(label), matching: find.byType(InkWell))
            .first,
      );
      expect(ink.onTap, isNotNull, reason: 'Hindi mapindot ang $label');
    }

    // Walang crash kahit walang mail/dialer app sa environment ng test.
    await tester.tap(find.text(AppConstants.supportEmail));
    await tester.pumpAndSettle();

    final faqCard = tester.getSize(find.byType(Card).first);
    final faqCenter = tester.getCenter(find.byType(Card).first);
    expect(faqCard.width, lessThanOrEqualTo(760),
        reason: 'Nakaunat pa rin ang FAQ sa buong lapad ng desktop');
    expect(faqCenter.dx, closeTo(640, 3),
        reason: 'Hindi naka-center ang Help Center content sa desktop');

    await disposeTree(tester);
  });
}
