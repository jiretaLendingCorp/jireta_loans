// test/features/head_manager/account_upgrade/account_upgrade_reject_modal_test.dart
//
// ACCOUNT UPGRADE REJECT — kapareho ng loan reject.
//
// Kailangang pumili muna ang staff kung kailan pwedeng mag-resubmit ang
// lender (Immediately / 1 month / ... / Other date / Permanent reject) bago
// naka-enable ang Reject. Walang default.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:jireta_loans/presentation/features/head_manager/loans/widgets/approve_reject_modal.dart';

void main() {
  setUpAll(() async {
    // Ginagamit ng picker hints ang AppFormatters.date (en_PH).
    await initializeDateFormatting('en_PH');
  });

  Future<void> pumpModal(
    WidgetTester tester,
    void Function(DateTime?, bool) onConfirm,
  ) async {
    // Sapat ang taas para buong picker (kasama ang Permanent reject) — para
    // hindi kailangang i-scroll sa test.
    tester.view.physicalSize = const Size(900, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ApproveRejectModal(
                  loanId: 'lender-1',
                  isApprove: false,
                  title: 'Reject Account Upgrade',
                  message:
                      'Do you want to reject this lender\'s account upgrade submission? This action cannot be undone.',
                  actionWord: 'resubmit',
                  onConfirm: (_, __, reapplyAllowedAt, permanent) {
                    onConfirm(reapplyAllowedAt, permanent);
                    // Gaya ng app: parent ang nag-po-pop matapos pindutin —
                    // kung hindi, tuloy-tuloy ang spinner sa Reject button.
                    Navigator.of(context).pop();
                  },
                ),
              ),
              child: const Text('Open reject'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open reject'));
    await tester.pumpAndSettle();
  }

  testWidgets('may resubmit picker; disabled ang Reject hangga\'t walang napili',
      (tester) async {
    DateTime? pickedDate;
    bool? pickedPermanent;
    await pumpModal(tester, (date, permanent) {
      pickedDate = date;
      pickedPermanent = permanent;
    });

    expect(find.text('Reject Account Upgrade'), findsOneWidget);
    expect(find.text('When can the lender resubmit again?'), findsOneWidget);
    expect(find.text('Immediately'), findsOneWidget);
    expect(find.text('1 month'), findsOneWidget);
    expect(find.text('Permanent reject'), findsOneWidget);

    // Walang default — hindi basta 1 month ang ipapadala.
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(pickedDate, isNull);
    expect(pickedPermanent, isNull);

    // Pumili ng Immediately → pwede agad (date ngayon).
    await tester.tap(find.text('Immediately'));
    await tester.pumpAndSettle();
    expect(
      find.text('The lender can resubmit again right away.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(pickedPermanent, isFalse);
    expect(pickedDate, isNotNull);
    expect(
      pickedDate!.difference(DateTime.now()).inSeconds.abs(),
      lessThan(5),
    );
  });

  testWidgets('Permanent reject → walang date, permanent ang ipapadala',
      (tester) async {
    DateTime? pickedDate;
    bool? pickedPermanent;
    await pumpModal(tester, (date, permanent) {
      pickedDate = date;
      pickedPermanent = permanent;
    });

    await tester.tap(find.text('Permanent reject'));
    await tester.pumpAndSettle();

    expect(
      find.text('Permanent: the lender can no longer resubmit again.'),
      findsOneWidget,
    );

    // Kapag permanent ang pinili, "Reject permanently" ang label ng button.
    await tester.tap(find.text('Reject permanently'));
    await tester.pumpAndSettle();
    expect(pickedPermanent, isTrue);
    expect(pickedDate, isNull);
  });
}
