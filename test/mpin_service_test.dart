// test/mpin_service_test.dart
//
// Tests para sa app-level 4-digit MPIN (rider / lender) — SERVER-SIDE na
// (account-level) ang MPIN ngayon:
//   * ang server ang nag-iimbak at nagve-verify (hindi na device-local),
//   * tama ang verify / wrong-attempt counting / lockout,
//   * humihiwalay ang "offline" (hindi maabot ang server) sa "maling MPIN",
//   * gumagana ang verify at setup dialog (kasama ang confirm step).
//
// Ang `MpinRemoteDataSource` ay pinalitan ng in-memory na `_FakeMpinServer`, at
// ang platform storage ng `SharedPreferences` / `FlutterSecureStorage` ay
// naka-mock (`setMockInitialValues`), kaya hindi kailangan ng totoong network o
// device.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/core/security/mpin_login_gate.dart';
import 'package:jireta_loans/core/security/mpin_service.dart';
import 'package:jireta_loans/core/security/secure_storage.dart';
import 'package:jireta_loans/data/datasources/remote/mpin_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/auth/screens/mpin_setup_screen.dart';
import 'package:jireta_loans/presentation/shared/widgets/security/mpin_dialog.dart';
import 'package:jireta_loans/presentation/shared/widgets/security/mpin_keypad.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory na kapalit ng server (`auth-mpin` edge function).
///
/// Kinokopya nito ang mahahalagang panuntunan ng server: 3 maling attempt →
/// 60s lockout, at 10 palit sa loob ng 15 araw (ang unang set-up ay libre).
class _FakeMpinServer implements MpinRemoteDataSource {
  String? pin;
  int failedAttempts = 0;
  int changes = 0;

  /// Hanggang kailan naka-lock (pagkatapos maubos ang attempts).
  DateTime? lockedUntil;

  /// Kapag `true`, "hindi maabot ang server" ang lahat ng tawag (offline).
  bool offline = false;

  static const int maxAttempts = 3;
  static const int maxChanges = 10;
  static const Duration lockout = Duration(seconds: 60);

  Never _noConnection() => throw StateError('offline (simulated)');

  int get _lockSecondsLeft {
    final until = lockedUntil;
    if (until == null) return 0;
    final left = until.difference(DateTime.now()).inSeconds;
    if (left <= 0) {
      lockedUntil = null;
      return 0;
    }
    return left;
  }

  @override
  Future<MpinStatusReply> status() async {
    if (offline) _noConnection();
    final lockSecs = _lockSecondsLeft;
    return MpinStatusReply(
      hasMpin: pin != null,
      lockRemaining: lockSecs > 0 ? Duration(seconds: lockSecs) : null,
      attemptsLeft: maxAttempts,
      changesRemaining: (maxChanges - changes).clamp(0, maxChanges),
      changeResetIn: changes >= maxChanges ? const Duration(days: 15) : null,
    );
  }

  @override
  Future<MpinVerifyReply> verify(String mpin) async {
    if (offline) _noConnection();
    if (pin == null) return const MpinVerifyReply(MpinVerifyOutcome.notSet);
    // Naka-lock: hindi tumatanggap kahit TAMA ang MPIN.
    final lockSecs = _lockSecondsLeft;
    if (lockSecs > 0) {
      return MpinVerifyReply(
        MpinVerifyOutcome.locked,
        lockRemaining: Duration(seconds: lockSecs),
      );
    }
    if (mpin == pin) {
      failedAttempts = 0;
      return const MpinVerifyReply(MpinVerifyOutcome.success);
    }
    failedAttempts++;
    if (failedAttempts >= maxAttempts) {
      failedAttempts = 0;
      lockedUntil = DateTime.now().add(lockout);
      return const MpinVerifyReply(
        MpinVerifyOutcome.locked,
        lockRemaining: lockout,
      );
    }
    return MpinVerifyReply(
      MpinVerifyOutcome.wrong,
      attemptsLeft: maxAttempts - failedAttempts,
    );
  }

  @override
  Future<MpinSetReply> setMpin({
    required String mpin,
    String? currentMpin,
  }) async {
    if (offline) _noConnection();
    final isChange = pin != null;
    if (isChange) {
      // Ang server ay may pangalawang tsek ng kasalukuyang MPIN.
      if (currentMpin != pin) {
        throw StateError('current MPIN mismatch (simulated server rejection)');
      }
      if (changes >= maxChanges) {
        return const MpinSetReply(
          saved: false,
          changeLimitRemaining: Duration(days: 15),
        );
      }
      changes++;
    }
    pin = mpin;
    failedAttempts = 0;
    return const MpinSetReply(saved: true);
  }

  @override
  Future<void> reset() async {
    if (offline) _noConnection();
    pin = null;
    failedAttempts = 0;
  }
}

/// Tinatanggap ang dialog at ibinabalik ang resulta ng `showMpinVerifyDialog`.
Widget _host(Future<void> Function(BuildContext) onPressed) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => onPressed(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

/// Naghihintay ng ilang frames. Hindi puwedeng `pumpAndSettle()` dito: may
/// naka-focus na `TextFormField` sa dialog, at ang patuloy na cursor blink ay
/// walang katapusang frames na nagpapa-hang sa `pumpAndSettle`.
Future<void> _pumpFrames(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Nagta-type ng 4 na digit sa MPIN boxes, isa-isa.
Future<void> _typePin(WidgetTester tester, String pin) async {
  for (var i = 0; i < pin.length; i++) {
    await tester.enterText(find.byType(TextFormField).at(i), pin[i]);
    await tester.pump();
  }
  await _pumpFrames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Malinis na device: walang secure storage at walang local na hint.
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('MpinService (server-side)', () {
    late _FakeMpinServer server;
    late MpinService service;

    setUp(() {
      server = _FakeMpinServer();
      service = MpinService(ds: server);
    });

    test('tatlong attempts lang bago ma-lock', () {
      // Sadyang 3 (hindi 5) — mahigpit na dahil 4-digit lang ang MPIN.
      expect(MpinService.maxAttempts, 3);
      expect(MpinService.maxChangesPerWindow, 10);
      expect(MpinService.changeWindow, const Duration(days: 15));
    });

    test('isValidFormat accepts only 4 digits', () {
      expect(MpinService.isValidFormat('1234'), isTrue);
      expect(MpinService.isValidFormat('0000'), isTrue);
      expect(MpinService.isValidFormat('123'), isFalse);
      expect(MpinService.isValidFormat('12345'), isFalse);
      expect(MpinService.isValidFormat('12a4'), isFalse);
      expect(MpinService.isValidFormat(''), isFalse);
    });

    test('isSet is false until the MPIN is saved on the account', () async {
      expect(await service.isSet(), isFalse);
      await service.setMpin('1234');
      expect(await service.isSet(), isTrue);
    });

    test('setMpin rejects a malformed PIN', () async {
      expect(() => service.setMpin('12'), throwsArgumentError);
      expect(server.pin, isNull);
      expect(await service.isSet(), isFalse);
    });

    test('verify succeeds with the correct MPIN', () async {
      await service.setMpin('1234');
      final result = await service.verify('1234');
      expect(result.isSuccess, isTrue);
      expect(result.status, MpinStatus.success);
    });

    test('verify counts failed attempts', () async {
      await service.setMpin('1234');
      for (var i = 1; i < MpinService.maxAttempts; i++) {
        final result = await service.verify('9999');
        expect(result.status, MpinStatus.wrong);
        expect(result.attemptsLeft, MpinService.maxAttempts - i);
      }
    });

    test('verify locks out after maxAttempts and reports the countdown',
        () async {
      await service.setMpin('1234');
      for (var i = 0; i < MpinService.maxAttempts; i++) {
        await service.verify('9999');
      }
      final locked = await service.verify('1234');
      expect(locked.status, MpinStatus.locked);
      expect(locked.lockRemaining, isNotNull);
    });

    test('a successful verify clears the failed-attempt counter', () async {
      await service.setMpin('1234');
      await service.verify('9999');
      await service.verify('9999');
      expect((await service.verify('1234')).isSuccess, isTrue);
      // Bumalik sa buong attempts budget ang user.
      final after = await service.verify('9999');
      expect(after.attemptsLeft, MpinService.maxAttempts - 1);
    });

    test('verify reports notSet when the account has no MPIN', () async {
      final result = await service.verify('1234');
      expect(result.status, MpinStatus.notSet);
    });

    test('verify reports offline (HINDI "wrong") kapag di maabot ang server',
        () async {
      await service.setMpin('1234');
      server.offline = true;
      final result = await service.verify('1234');
      expect(result.status, MpinStatus.offline,
          reason: 'Server-side ang verification — offline ≠ maling MPIN');
      expect(result.status, isNot(MpinStatus.wrong));
    });

    test('clear removes the MPIN', () async {
      await service.setMpin('1234');
      await service.clear();
      expect(await service.isSet(), isFalse);
      expect((await service.verify('1234')).status, MpinStatus.notSet);
    });

    test('changing the MPIN consumes the 15-day quota, unang set-up libre',
        () async {
      await service.setMpin('1234');
      expect(server.changes, 0, reason: 'Ang unang set-up ay hindi binibilang');
      await service.setMpin('5678', currentMpin: '1234');
      expect(server.changes, 1);
      expect((await service.verify('5678')).isSuccess, isTrue);
    });

    test('setMpin throws MpinChangeLimitException kapag puno na ang quota',
        () async {
      await service.setMpin('1234');
      for (var i = 0; i < MpinService.maxChangesPerWindow; i++) {
        await service.setMpin('$i$i$i$i', currentMpin: server.pin!);
      }
      expect(
        () => service.setMpin('9999', currentMpin: server.pin!),
        throwsA(isA<MpinChangeLimitException>()),
      );
      final quota = await service.changeQuota();
      expect(quota.remaining, 0);
      expect(quota.resetIn, isNotNull);
    });

    test('changeQuota reports the remaining changes from the server', () async {
      await service.setMpin('1234');
      final quota = await service.changeQuota();
      expect(quota.remaining, MpinService.maxChangesPerWindow);
      expect(quota.resetIn, isNull);
    });

    test(
        'ACCOUNT-level: makikita pa rin ang MPIN kahit bagong install '
        '(walang lokal na storage)', () async {
      // Bagong device / wiped device: walang laman ang secure storage at
      // SharedPreferences, pero may MPIN na ang ACCOUNT sa server.
      await service.setMpin('1234');
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});

      final fresh = MpinService(ds: server);
      expect(await fresh.isSet(), isTrue);
      expect((await fresh.verify('1234')).isSuccess, isTrue);
    });

    test(
        'offline: gamitin ang HULING nalalaman na status (hint), hindi ang '
        'MPIN mismo', () async {
      // Kailangan ng user id para may scope ang naka-cache na hint.
      await SecureStorage.saveUserInfo(userId: 'u-1', role: 'lender');
      await service.setMpin('1234'); // naka-cache ang hint = true
      server.offline = true;
      final offlineService = MpinService(ds: server);
      expect(await offlineService.isSet(), isTrue,
          reason: 'Naka-cache na "may MPIN" ang account na ito');

      // Kapag walang naka-cache na hint (bagong install habang offline) ay
      // hindi na ito magpapanggap na may MPIN.
      SharedPreferences.setMockInitialValues({});
      final unknown = MpinService(ds: server);
      expect(await unknown.isSet(), isFalse);
    });

    test('statusHasMpin: true / false mula sa server', () async {
      expect(await service.statusHasMpin(), isFalse,
          reason: 'Tahasang wala pang MPIN sa account');
      await service.setMpin('1234');
      expect(await service.statusHasMpin(), isTrue);
    });

    test(
        'statusHasMpin: null (HINDI false) kapag hindi maabot ang server at '
        'walang local na hint', () async {
      // Ito ang sanhi ng "nag-create ng MPIN kahit may MPIN na": sa
      // change-number flow, wala pang local na hint ang BAGONG numero sa device
      // na ito — kapag bigong makuha ang status, dapat "hindi matiyak" (null)
      // ito at hindi "wala pang MPIN".
      server.offline = true;
      expect(await service.statusHasMpin(), isNull);
      // Ang `isSet()` ay best-effort pa rin (false) — kaya hindi ito dapat
      // gamitin sa "create vs enter" na desisyon.
      expect(await service.isSet(), isFalse);
    });

    test('statusHasMpin: gamitin ang huling nalalaman kapag offline', () async {
      await SecureStorage.saveUserInfo(userId: 'u-1', role: 'lender');
      await service.setMpin('1234'); // naka-cache na: may MPIN ang account
      server.offline = true;
      expect(await service.statusHasMpin(), isTrue);
    });
  });

  group('mpinStepAfterOtp (create vs enter pagkatapos ng OTP)', () {
    test('tahasang wala pang MPIN → create', () {
      expect(mpinStepAfterOtp(false), MpinAfterOtpStep.create);
    });

    test('may MPIN → enter (hindi na mag-create)', () {
      expect(mpinStepAfterOtp(true), MpinAfterOtpStep.enter);
    });

    test('hindi matiyak (null) → enter, huwag ipilit ang create', () {
      expect(mpinStepAfterOtp(null), MpinAfterOtpStep.enter);
    });
  });

  group('MpinDialog', () {
    testWidgets('verify pops true for the correct MPIN', (tester) async {
      final server = _FakeMpinServer();
      final service = MpinService(ds: server);
      await service.setMpin('1234');

      bool? verified;
      await tester.pumpWidget(_host((context) async {
        verified = await showMpinVerifyDialog(context, mpin: service);
      }));
      await tester.tap(find.text('open'));
      await _pumpFrames(tester);

      expect(find.text('Enter MPIN'), findsOneWidget);

      await _typePin(tester, '1234');
      expect(verified, isTrue);
      await _pumpFrames(tester);
      expect(find.text('Enter MPIN'), findsNothing);
    });

    testWidgets('verify shows an error and stays open for a wrong MPIN',
        (tester) async {
      final server = _FakeMpinServer();
      final service = MpinService(ds: server);
      await service.setMpin('1234');

      bool? verified;
      await tester.pumpWidget(_host((context) async {
        verified = await showMpinVerifyDialog(context, mpin: service);
      }));
      await tester.tap(find.text('open'));
      await _pumpFrames(tester);

      await _typePin(tester, '9999');
      expect(verified, isNull);
      expect(find.textContaining('Incorrect MPIN'), findsOneWidget);
      expect(find.text('Enter MPIN'), findsOneWidget);

      // Sunod na tama pa rin ang tatanggapin.
      await _typePin(tester, '1234');
      expect(verified, isTrue);
    });

    testWidgets('verify shows the offline message kapag di maabot ang server',
        (tester) async {
      final server = _FakeMpinServer()..offline = true;
      final service = MpinService(ds: server);

      bool? verified;
      await tester.pumpWidget(_host((context) async {
        verified = await showMpinVerifyDialog(context, mpin: service);
      }));
      await tester.tap(find.text('open'));
      await _pumpFrames(tester);

      await _typePin(tester, '1234');
      expect(verified, isNull);
      expect(find.textContaining('internet connection'), findsOneWidget);
      expect(find.textContaining('Incorrect MPIN'), findsNothing);
    });

    testWidgets('setup asks to confirm and saves the MPIN', (tester) async {
      final server = _FakeMpinServer();
      final service = MpinService(ds: server);

      bool? saved;
      await tester.pumpWidget(_host((context) async {
        saved = await showMpinSetupDialog(context, mpin: service);
      }));
      await tester.tap(find.text('open'));
      await _pumpFrames(tester);

      expect(find.text('Create 4-Digit MPIN'), findsOneWidget);
      await _typePin(tester, '1234');
      expect(find.text('Confirm MPIN'), findsOneWidget);

      // Mali ang confirm → error, at hindi pa naka-save.
      await _typePin(tester, '4321');
      expect(find.textContaining('did not match'), findsOneWidget);
      expect(await service.isSet(), isFalse);

      // Ulitin: tama na ngayon ang confirm.
      await _typePin(tester, '1234');
      expect(find.text('Confirm MPIN'), findsOneWidget);
      await _typePin(tester, '1234');
      await _pumpFrames(tester);

      expect(saved, isTrue);
      expect(await service.isSet(), isTrue);
      expect((await service.verify('1234')).isSuccess, isTrue);
    });

    testWidgets('change-with-current: ipinapasa ang verified na lumang MPIN',
        (tester) async {
      final server = _FakeMpinServer()..pin = '1234';
      final service = MpinService(ds: server);

      bool? saved;
      await tester.pumpWidget(_host((context) async {
        saved = await showMpinSetupDialog(
          context,
          requireCurrent: true,
          mpin: service,
        );
      }));
      await tester.tap(find.text('open'));
      await _pumpFrames(tester);

      // Kasalukuyang MPIN muna...
      expect(find.text('Current MPIN'), findsOneWidget);
      await _typePin(tester, '1234');
      // ...tapos ang bago (create + confirm).
      await _typePin(tester, '5678');
      await _typePin(tester, '5678');
      await _pumpFrames(tester);

      expect(saved, isTrue);
      expect(server.pin, '5678');
      expect(server.changes, 1);
    });

    testWidgets('required-MPIN setup shows the explanation copy',
        (tester) async {
      final service = MpinService(ds: _FakeMpinServer());
      await tester.pumpWidget(_host((context) async {
        await showMpinSetupDialog(
          context,
          reason: 'Walang password ang phone mo — mag-set ng MPIN.',
          mpin: service,
        );
      }));
      await tester.tap(find.text('open'));
      await _pumpFrames(tester);

      expect(find.text('Walang password ang phone mo — mag-set ng MPIN.'),
          findsOneWidget);
    });

    testWidgets('ang "did not match" ay kusang nawawala pagkatapos ng 3s',
        (tester) async {
      final service = MpinService(ds: _FakeMpinServer());
      await tester.pumpWidget(_host((context) async {
        await showMpinSetupDialog(context, mpin: service);
      }));
      await tester.tap(find.text('open'));
      await _pumpFrames(tester);

      await _typePin(tester, '1234');
      await _typePin(tester, '4321');
      expect(find.textContaining('did not match'), findsOneWidget);

      // Pagkalipas ng 3 segundo (4 na pump para sigurado), kusang nawawala.
      await tester.pump(const Duration(seconds: 4));
      expect(find.textContaining('did not match'), findsNothing);
      // Bumalik sa unang hakbang — handa sa bagong MPIN.
      expect(find.text('Create 4-Digit MPIN'), findsOneWidget);
    });
  });

  group('MpinSetupScreen', () {
    /// Pinipindot ang mga keypad key ayon sa pagkakasunod-sunod.
    Future<void> tapKeys(WidgetTester tester, List<String> keys) async {
      for (final key in keys) {
        await tester.tap(find.text(key));
        await tester.pump();
      }
      await tester.pump();
    }

    Future<void> pumpSetup(WidgetTester tester, MpinService service) async {
      // Sapat ang taas para hindi matakpan ng scroll view ang keypad.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mpinServiceProvider.overrideWithValue(service)],
          child: const MaterialApp(home: MpinSetupScreen()),
        ),
      );
      await tester.pump();
    }

    testWidgets(
        'ang "did not match" ay nasa ILALIM ng 4 na tuldok at nawawala sa 3s',
        (tester) async {
      final service = MpinService(ds: _FakeMpinServer());
      await pumpSetup(tester, service);

      expect(find.text('Create Your MPIN'), findsOneWidget);
      await tapKeys(tester, ['1', '2', '3', '4']);
      expect(find.text('Confirm MPIN'), findsOneWidget);

      // Hindi tugma ang kumpirmasyon → lumalabas ang mensahe.
      await tapKeys(tester, ['4', '3', '2', '1']);
      expect(find.textContaining('did not match'), findsOneWidget);

      // Nasa ILALIM ito ng 4 na tuldok (at nasa ITAAS ng keypad) — dati ay nasa
      // ibaba pa ng keypad ang mensahe.
      final dotsY = tester.getCenter(find.byType(MpinDots)).dy;
      final errorY = tester.getCenter(find.textContaining('did not match')).dy;
      final keypadY = tester.getCenter(find.byType(MpinKeypadField)).dy;
      expect(errorY, greaterThan(dotsY));
      expect(errorY, lessThan(keypadY));

      // Pagkalipas ng 3 segundo, kusang nawawala.
      await tester.pump(const Duration(seconds: 4));
      expect(find.textContaining('did not match'), findsNothing);
      // Hindi pa na-save ang MPIN dahil hindi natuloy ang kumpirmasyon.
      expect(await service.isSet(), isFalse);
    });
  });
}
