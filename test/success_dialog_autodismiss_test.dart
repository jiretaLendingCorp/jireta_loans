// test/success_dialog_autodismiss_test.dart
//
// Ang "Successfully Reset MPIN" na dialog pagkatapos ma-verify ang OTP sa
// reset flow ay kusang nagsasara pagkalipas ng 2 segundo
// (`SuccessDialog.showAutoDismiss`). Tinitiyak dito na:
//   * nakalabas ito agad pagkatapos ng verification, at
//   * wala na ito pagkalipas ng 2 segundo (hindi nananatiling nakabitin).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/presentation/shared/widgets/dialogs/success_dialog.dart';

void main() {
  Widget buildHost() => MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => SuccessDialog.showAutoDismiss(
                  context,
                  title: 'Successfully Reset MPIN',
                  message: 'Your OTP has been verified and your old MPIN '
                      'has been reset. Create your new MPIN now.',
                  duration: const Duration(seconds: 2),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('kusang nagsasara pagkalipas ng 2 segundo', (tester) async {
    await tester.pumpWidget(buildHost());

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Successfully Reset MPIN'), findsOneWidget);

    // Bago pa matapos ang 2 segundo, nandito pa ito.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Successfully Reset MPIN'), findsOneWidget);

    // Pagkalipas ng 2 segundo, wala na.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Successfully Reset MPIN'), findsNothing);
  });
}
