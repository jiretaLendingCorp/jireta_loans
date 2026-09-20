// test/mpin_keypad_test.dart
//
// Tests para sa MPIN dots + numeric keypad na ginagamit ng login page at ng
// MPIN setup screen:
//   * kumpletong 4-digit lang ang isinusumite,
//   * gumagana ang backspace, at
//   * nila-clear ng controller ang naipasok (hal. pagkatapos ng maling MPIN).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/shared/widgets/security/mpin_keypad.dart';

Widget _host({
  required ValueChanged<String> onCompleted,
  MpinPadController? controller,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: MpinKeypadField(
          controller: controller,
          onCompleted: onCompleted,
        ),
      ),
    ),
  );
}

/// Pinipindot ang mga keypad key ayon sa pagkakasunod-sunod na ibinigay.
Future<void> _tapKeys(WidgetTester tester, List<String> keys) async {
  for (final key in keys) {
    await tester.tap(find.text(key));
    await tester.pump();
  }
  // Isa pang frame para tumakbo ang post-frame na `onCompleted`.
  await tester.pump();
}

void main() {
  testWidgets('ipinapadala ang buong 4-digit MPIN kapag napuno na',
      (tester) async {
    String? completed;
    await tester.pumpWidget(_host(onCompleted: (pin) => completed = pin));

    // Hindi pa kumpleto → wala pang isinusumite.
    await _tapKeys(tester, ['1', '2', '3']);
    expect(completed, isNull);

    await _tapKeys(tester, ['4']);
    expect(completed, '1234');
  });

  testWidgets('binubura ng backspace ang huling digit', (tester) async {
    String? completed;
    await tester.pumpWidget(_host(onCompleted: (pin) => completed = pin));

    await _tapKeys(tester, ['1', '2', '3', '9']);
    expect(completed, '1239');

    // 4 na digit lang ang tinatanggap — dagdag na pindot ay walang epekto,
    // kaya kailangan munang burahin bago makapag-type muli.
    await _tapKeys(tester, ['5']);
    expect(completed, '1239');

    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    await _tapKeys(tester, ['4']);
    expect(completed, '1234');
  });

  testWidgets('nila-clear ng controller ang naipasok', (tester) async {
    String? completed;
    final controller = MpinPadController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(onCompleted: (pin) => completed = pin, controller: controller),
    );

    await _tapKeys(tester, ['9', '9']);
    controller.clear();
    await tester.pump();

    // Kung hindi na-clear, ang sunod na 4 na pindot ay hindi magiging '1234'.
    await _tapKeys(tester, ['1', '2', '3', '4']);
    expect(completed, '1234');
  });

  test('formatMpinPhone ay ipinapakita ang buong numero sa +63 format', () {
    expect(formatMpinPhone('09171234567'), '+63 917 123 4567');
    expect(formatMpinPhone('0912 345 2121'), '+63 912 345 2121');
    // Naka-63 na agad → hindi na doblehin.
    expect(formatMpinPhone('+63 912 345 2121'), '+63 912 345 2121');
    // Hindi kumpleto (hal. hindi pa 11 digit) → ibinalik as-is.
    expect(formatMpinPhone('0917'), '0917');
  });
}
