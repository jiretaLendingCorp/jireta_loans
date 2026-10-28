// test/features/head_manager/lenders/lender_details_label_test.dart
//
// Sa Lenders section, "Lendee" ang label ng role. Ang shared user-details modal
// ay may `roleLabelOverride` para manatiling "Lender" ang label sa ibang
// sections (All People, Archived, atbp.).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/shared/widgets/details/user_details_modal.dart';

UserModel _lender() => UserModel(
      id: 'lender-1',
      role: 'lender',
      firstName: 'April',
      lastName: 'Malasan',
      email: 'april123@gmail.com',
      accountStatus: 'active',
      forcePasswordChange: false,
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _pumpAndOpen(
  WidgetTester tester, {
  String? roleLabelOverride,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showUserDetailsModal(
              context,
              _lender(),
              roleLabelOverride: roleLabelOverride,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Lenders modal: Lendee ang label kapag may override',
      (tester) async {
    await _pumpAndOpen(tester, roleLabelOverride: 'Lendee');

    expect(find.text('Lendee Details'), findsOneWidget);
    expect(find.text('LENDEE'), findsOneWidget);
    expect(find.text('Lender Details'), findsNothing);
  });

  testWidgets('Ibang sections: Lender pa rin ang default', (tester) async {
    await _pumpAndOpen(tester);

    expect(find.text('Lender Details'), findsOneWidget);
    expect(find.text('LENDER'), findsOneWidget);
  });
}
