// test/mpin_service_test.dart
//
// Tests para sa app-level 4-digit MPIN (rider / lender):
//   * hindi plain-text ang naka-store (SHA-256 + salt),
//   * tama ang verify / wrong-attempt counting / lockout,
//   * gumagana ang verify at setup dialog (kasama ang confirm step).
//
// Ang device storage ay pinalitan ng in-memory na `_MemorySecureStorage` kaya
// hindi kailangan ng platform plugin sa test.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/core/security/mpin_service.dart';
import 'package:jireta_loans/presentation/shared/widgets/security/mpin_dialog.dart';

/// In-memory na kapalit ng `FlutterSecureStorage`.
class _MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};

  /// Para ma-check na hindi plain ang naka-store na MPIN.
  Map<String, String> get raw => Map.unmodifiable(_data);

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _data[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
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
  // Ang `SecureStorage.getUserId()` — gamit ng `MpinService` para i-scope ang
  // MPIN sa bawat account — ay dumadaan sa platform channel ng
  // `flutter_secure_storage`. Sa widget test ay walang tumutugon doon, kaya
  // hinihintay nito nang walang hanggan. I-mock ito para sumagot agad ng
  // `null` (→ `guest` scope), sapat na para sa mga test sa ibaba.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  group('MpinService', () {
    late _MemorySecureStorage storage;
    late MpinService service;

    setUp(() {
      storage = _MemorySecureStorage();
      service = MpinService(storage: storage);
    });

    test('isValidFormat accepts only 4 digits', () {
      expect(MpinService.isValidFormat('1234'), isTrue);
      expect(MpinService.isValidFormat('0000'), isTrue);
      expect(MpinService.isValidFormat('123'), isFalse);
      expect(MpinService.isValidFormat('12345'), isFalse);
      expect(MpinService.isValidFormat('12a4'), isFalse);
      expect(MpinService.isValidFormat(''), isFalse);
    });

    test('isSet is false until setMpin is called', () async {
      expect(await service.isSet(), isFalse);
      await service.setMpin('1234');
      expect(await service.isSet(), isTrue);
    });

    test('setMpin rejects a malformed PIN', () async {
      expect(() => service.setMpin('12'), throwsArgumentError);
      expect(await service.isSet(), isFalse);
    });

    test('the stored value is never the plain MPIN', () async {
      await service.setMpin('2468');
      expect(await service.isSet(), isTrue);
      for (final value in storage.raw.values) {
        expect(value.contains('2468'), isFalse,
            reason: 'May plain-text na MPIN sa storage');
      }
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
      expect(await service.lockRemaining(), isNotNull);

      // Naka-lock kahit tama ang MPIN.
      final duringLock = await service.verify('1234');
      expect(duringLock.status, MpinStatus.locked);
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

    test('verify reports notSet when no MPIN was ever saved', () async {
      final result = await service.verify('1234');
      expect(result.status, MpinStatus.notSet);
    });

    test('clear removes the MPIN', () async {
      await service.setMpin('1234');
      await service.clear();
      expect(await service.isSet(), isFalse);
      expect((await service.verify('1234')).status, MpinStatus.notSet);
    });
  });

  group('MpinDialog', () {
    testWidgets('verify pops true for the correct MPIN', (tester) async {
      final service = MpinService(storage: _MemorySecureStorage());
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
      final service = MpinService(storage: _MemorySecureStorage());
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

    testWidgets('setup asks to confirm and saves the MPIN', (tester) async {
      final service = MpinService(storage: _MemorySecureStorage());

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

    testWidgets('required-MPIN setup shows the explanation copy',
        (tester) async {
      final service = MpinService(storage: _MemorySecureStorage());
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
  });
}
