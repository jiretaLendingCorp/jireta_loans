// test/features/head_manager/rider_monitoring/rider_monitoring_details_render_test.dart
//
// REGRESSION: `NoSuchMethodError: 'toPeso'` sa account card ng details page.
// Ang sanhi ay `dynamic` ang receiver ng extension method. Sinusuri dito ang
// buong details body na may JSON numbers (int/double) at walang exception.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:jireta_loans/data/models/rider_collection_monitoring_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_monitoring/screens/hm_rider_monitoring_details_screen.dart';

final _detail = RiderMonitoringDetail(
  rider: const {
    'rider_name': 'Anthony Maramba',
    'phone_number': '09635267491',
    'plate_number': 'PRT-6817',
    'vehicle_type': 'Motorcycle',
    'is_available': true,
    'joined_at': '2026-09-23T00:00:00.000Z',
    'address': 'Highway Street, Tuliao, Santa Barbara, Pampanga',
  },
  summary: const RiderMonitoringSummary(
    expectedCollection: 20000,
    confirmedCollection: 20000,
    remainingDue: 0,
    assignedInstallments: 2,
    overdueAccounts: 0,
  ),
  accounts: [
    {
      'loan_number': 'LN-2026-760880',
      'loan_status': 'active',
      'lender_name': 'April Malasan',
      'outstanding_balance': 20000,
      'assigned_installments': 1,
      'expected_collection': 20000,
      'confirmed_collection': 20000,
      'remaining_due': 0,
      'overdue_installments': 0,
      'schedules': [
        {
          'installment_number': 1,
          'due_date': '2026-10-15',
          'amount_due': 20000,
          'amount_paid': 20000,
          'remaining_due': 0,
          'status': 'paid',
          'confirmed_collection': 20000,
        },
      ],
    },
  ],
  payments: [
    {
      'amount': 20000,
      'status': 'verified',
      'paid_at': '2026-10-16T02:00:00.000Z',
      'loan_number': 'LN-2026-760880',
      'lender_name': 'April Malasan',
      'installment_number': 1,
    },
  ],
  history: [
    {
      'status': 'completed',
      'amount_collected': 20000,
      'activity_at': '2026-10-16T02:00:00.000Z',
      'loan_number': 'LN-2026-760880',
      'lender_name': 'April Malasan',
      'installment_number': 1,
    },
  ],
);

void main() {
  setUpAll(() async {
    // Ang shared `AppFormatters` ay gumagamit ng `en_PH` DateFormat.
    await initializeDateFormatting('en_PH', null);
  });

  testWidgets('details body renders money values at desktop width',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1062,
          child: RiderMonitoringDetailBody(detail: _detail),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Anthony Maramba'), findsOneWidget);
    expect(find.text('All dates'), findsOneWidget);
    expect(find.text('April Malasan'), findsWidgets);
    expect(find.text('₱20,000.00'), findsWidgets);
    expect(find.text('Assigned Lenders & Loan Accounts'), findsOneWidget);
    expect(find.text('Confirmed Payments'), findsOneWidget);
    expect(find.text('Collection History'), findsOneWidget);
  });
}
