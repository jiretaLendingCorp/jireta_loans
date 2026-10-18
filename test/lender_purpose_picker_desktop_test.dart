// test/lender_purpose_picker_desktop_test.dart
//
// DESKTOP LAYOUT NG PURPOSE SCREEN (unang hakbang ng 2-step re-apply)
//
// ANO ANG TINITIGNAN NITO
//   • Desktop (>= kDesktopBreakpoint): naka-center sa max 960px ang content at
//     2 columns ang purposes — hindi naka-stretch sa buong browser.
//   • Mobile: isang column at buong lapad pa rin.
//   • Parehong nasa loob ng screen ang Continue button (walang overflow).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/presentation/features/lender/loans/screens/lender_apply_loan_screen.dart';

const _suggestions = <(String, IconData)>[
  ('Business Capital', Icons.storefront_outlined),
  ('Emergency / Medical', Icons.local_hospital_outlined),
  ('Education', Icons.school_outlined),
  ('Home Improvement', Icons.home_outlined),
  ('Debt Consolidation', Icons.account_balance_outlined),
  ('Travel', Icons.flight_takeoff_outlined),
  ('Other', Icons.more_horiz),
];

Widget _wrap() => MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFFF2F4F7),
        body: LenderLoanPurposePicker(
          suggestions: _suggestions,
          onSelected: (_) {},
        ),
      ),
    );

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desktop: 2 columns at naka-center sa 960px', (tester) async {
    await _pumpAt(tester, const Size(1280, 800));

    expect(tester.takeException(), isNull);

    final business = tester.getRect(find.text('Business Capital'));
    final emergency = tester.getRect(find.text('Emergency / Medical'));
    final education = tester.getRect(find.text('Education'));

    // Magkatabi sa unang row (2 columns).
    expect((business.center.dy - emergency.center.dy).abs(), lessThan(1));
    expect(education.center.dy, greaterThan(business.center.dy));

    // Naka-center: may margin sa kaliwa at kanan, hindi dikit sa gilid.
    final continueBtn = tester.getRect(find.text('Continue'));
    expect(continueBtn.left, greaterThan(1280 * 0.45));
    expect(continueBtn.right, lessThan(1280 - 16));

    // Ang buong content ay 960px lang ang lapad, naka-center sa screen.
    const contentLeft = (1280 - 960) / 2;
    expect(business.left, greaterThan(contentLeft));
  });

  testWidgets('mobile: isang column at buong lapad pa rin', (tester) async {
    await _pumpAt(tester, const Size(400, 800));

    expect(tester.takeException(), isNull);

    final business = tester.getRect(find.text('Business Capital'));
    final emergency = tester.getRect(find.text('Emergency / Medical'));

    // Magkaibang row (isang column).
    expect(emergency.center.dy, greaterThan(business.center.dy));

    // Buong lapad pa rin (walang 960px centering sa mobile): 16px page padding
    // + 14px tile padding + icon/gap lang ang space bago ang label.
    expect(business.left, lessThan(70));

    final continueBtn = tester.getRect(find.text('Continue'));
    expect(continueBtn.right, lessThanOrEqualTo(400 - 16 + 1));
  });
}
