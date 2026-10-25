// test/mobile_login_reset_mpin_cooldown_test.dart
//
// "Reset MPIN" sa MPIN screen ng login kapag naka-cooldown pa ang OTP ng numero
// (hal. kaka-send lang ng OTP sa pag-login): 429 OTP_RESEND_COOLDOWN ang sagot
// ng `auth-otp` kahit unang pindot pa lang ng user.
//
// Dati, ang RAW server text ang direktang inilalagay sa `_mpinError`, kaya
// pulang-pula at punô ang 4 na tuldok (parang tinanggihan ang naipasok) at
// hindi kailanman nawawala ang mensahe. Ngayon: neutral na countdown, naka-
// disable ang "Reset MPIN", at kusang bumabalik pagkatapos ng countdown.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jireta_loans/core/security/mpin_login_gate.dart';
import 'package:jireta_loans/data/datasources/remote/auth_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/auth/providers/auth_provider.dart';
import 'package:jireta_loans/presentation/features/auth/screens/mobile_login_screen.dart';
import 'package:jireta_loans/presentation/shared/providers/auth_state_provider.dart';
import 'package:jireta_loans/presentation/shared/providers/connectivity_provider.dart';
import 'package:jireta_loans/presentation/shared/widgets/security/mpin_keypad.dart';

/// Kapareho ng sagot ng `auth-otp` kapag may kamamatay na OTP ang numero.
class _CooldownAuthRemoteDataSource implements AuthRemoteDataSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Map<String, dynamic>> sendOtp({
    required String identifier,
    String purpose = 'login',
  }) async {
    final options = RequestOptions(path: '/auth-otp');
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(
        requestOptions: options,
        statusCode: 429,
        data: {
          'error': {
            'code': 'OTP_RESEND_COOLDOWN',
            'message': 'Please wait 15 second(s) before requesting a new code.',
            'retry_after_seconds': 15,
          },
        },
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpMpin(WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        connectivityProvider.overrideWith((ref) => Stream<bool>.value(true)),
        // Ang provider ang may-ari ng notifier para ma-dispose ito (kasama ang
        // mga timer nito) kapag bumaba ang widget tree.
        authStateProvider.overrideWith((ref) => AuthStateNotifier()),
        authProvider.overrideWith((ref) => AuthNotifier(
            _CooldownAuthRemoteDataSource(),
            ref.watch(authStateProvider.notifier))),
      ],
      child: const MaterialApp(
        home: MobileLoginScreen(
          handoff: MpinLoginChoice(showMpin: true, phone: '09171234567'),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> disposeTree(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets('cooldown ng reset: neutral na countdown, hindi pulang tuldok',
      (tester) async {
    await pumpMpin(tester);
    expect(find.text('Enter MPIN'), findsOneWidget);

    await tester.ensureVisible(find.text('Reset MPIN'));
    await tester.tap(find.text('Reset MPIN'));
    // Loading modal → natapos ang sendOtp (429) → nasara ang modal.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Countdown sa mensahe at sa button — hindi ang raw server text.
    expect(find.text('You can request a new code in 15s.'), findsOneWidget);
    expect(find.text('Try again in 15s'), findsOneWidget);
    expect(find.textContaining('Please wait 15 second(s)'), findsNothing);

    final button = tester.widget<TextButton>(find.ancestor(
      of: find.text('Try again in 15s'),
      matching: find.byType(TextButton),
    ));
    expect(button.onPressed, isNull,
        reason: 'Naka-enable pa rin ang Reset MPIN habang naka-cooldown');

    // Hindi ito maling MPIN — hindi dapat pumula/punô ang 4 na tuldok.
    final dots = tester.widget<MpinDots>(find.byType(MpinDots));
    expect(dots.hasError, isFalse);

    // Natapos ang 15s na cooldown → kusang bumabalik ang button at nawawala
    // ang mensahe, walang kailangang i-refresh.
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();

    expect(find.text('You can request a new code in 15s.'), findsNothing);
    expect(find.text('Try again in 15s'), findsNothing);
    final reEnabled = tester.widget<TextButton>(find.ancestor(
      of: find.text('Reset MPIN'),
      matching: find.byType(TextButton),
    ));
    expect(reEnabled.onPressed, isNotNull);

    await disposeTree(tester);
  });
}
