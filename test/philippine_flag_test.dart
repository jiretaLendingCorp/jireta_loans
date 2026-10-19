// test/philippine_flag_test.dart
//
// Ang `🇵🇭` emoji ay lumalabas na blangkong kahon sa Windows/Chrome (walang
// color-emoji flag glyph). Ito ang regression test para sa iginuhit na
// `PhilippineFlag` widget at para siguraduhing hindi na bumalik ang emoji sa
// mga auth screen.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/presentation/shared/widgets/philippine_flag.dart';

void main() {
  testWidgets('PhilippineFlag: iginuhit at may tamang 2:1 na sukat',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(child: PhilippineFlag(width: 20)),
    ));

    expect(find.byType(PhilippineFlag), findsOneWidget);
    expect(tester.getSize(find.byType(PhilippineFlag)), const Size(20, 10));
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('walang flag emoji sa auth screens', () {
    for (final path in const [
      'lib/presentation/features/auth/screens/mobile_login_screen.dart',
      'lib/presentation/features/auth/screens/mpin_setup_screen.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src.contains('🇵🇭'), isFalse,
          reason: '$path: gamitin ang PhilippineFlag widget, hindi ang emoji');
      expect(src, contains('PhilippineFlag'));
    }
  });
}
