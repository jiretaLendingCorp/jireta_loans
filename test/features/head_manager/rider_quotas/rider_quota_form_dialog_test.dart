// test/features/head_manager/rider_quotas/rider_quota_form_dialog_test.dart
//
// ENHANCED "Edit / Assign rider quota" DIALOG
//
//   * May branded header (rider name ang subtitle), sectioned form, period
//     pills (Daily / Weekly / Monthly), date tiles + range summary, at fixed
//     footer na laging maabot ang Save.
//   * Naka-comma separator agad ang target amount (100,000).
//   * Ang pagpalit ng period ay awtomatikong nagse-set ng default window.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/utils/timezone.dart';
import 'package:jireta_loans/data/datasources/remote/collection_remote_datasource.dart';
import 'package:jireta_loans/data/models/rider_quota_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_quotas/providers/hm_rider_quotas_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_quotas/widgets/rider_quota_form_dialog.dart';

import '../../../helpers/audit_test_helpers.dart';

class _OfflineDio extends FakeDioClient {
  _OfflineDio()
      : super((o) async => Response<dynamic>(
            requestOptions: o,
            data: {
              'data': <dynamic>[],
              'meta': {'unread_count': 0, 'total': 0},
            },
          ));
}

class _StubQuotasNotifier extends HmRiderQuotasNotifier {
  _StubQuotasNotifier() : super(CollectionRemoteDataSource(_OfflineDio())) {
    state = const HmRiderQuotasState();
  }

  @override
  Future<void> load({int page = 1, bool silent = false}) async {}
}

RiderQuota _weeklyQuota() => RiderQuota.fromJson({
      'quota_id': 'q1',
      'rider_id': 'r1',
      'rider_name': 'Jay Shin',
      'period': 'weekly',
      'target_amount': 100000,
      'confirmed_collection': 5000,
      'remaining_target': 95000,
      'completion_percentage': 5,
      'start_date': '2026-10-19',
      'end_date': '2026-10-25',
      'status': 'active',
      'is_active': true,
      'achieved': false,
      'payment_count': 1,
    });

void main() {
  setUpAll(() async {
    await loadTestEnv();
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    double width = 1000,
    RiderQuota? existing,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hmRiderQuotasProvider
              .overrideWith((ref) => _StubQuotasNotifier()),
          riderQuotaRiderOptionsProvider
              .overrideWith((ref) async => <RiderQuotaRiderOption>[
                    const RiderQuotaRiderOption(
                      riderId: 'r1',
                      riderName: 'Jay Shin',
                      phoneNumber: '09156882724',
                    ),
                  ]),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RiderQuotaFormDialog(existing: existing),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('edit mode: header, formatted amount, range summary, footer',
      (tester) async {
    await pumpDialog(tester, existing: _weeklyQuota());

    expect(tester.takeException(), isNull);
    expect(find.text('Edit rider quota'), findsOneWidget);
    // Rider name sa header subtitle.
    expect(find.text('Jay Shin'), findsOneWidget);
    // Period pills at mga section label.
    expect(find.text('Quota period'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Target amount'), findsOneWidget);
    expect(find.text('Quota window'), findsOneWidget);
    expect(find.text('Start date'), findsOneWidget);
    expect(find.text('End date'), findsOneWidget);
    // Naka-currency format agad ang halaga (comma + 2 decimals).
    expect(find.text('100,000.00'), findsOneWidget);
    expect(find.textContaining('₱100,000.00'), findsWidgets);
    // Buod ng window — 7 araw ang existing na weekly quota.
    expect(find.textContaining('7 days'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('pagpalit ng period → default window ng bagong period',
      (tester) async {
    await pumpDialog(tester, existing: _weeklyQuota());

    final monthly = riderQuotaDefaultRange(RiderQuotaPeriod.monthly, nowManila());
    final days = monthly.end.difference(monthly.start).inDays + 1;

    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();

    expect(find.textContaining('$days days'), findsOneWidget);
    expect(find.textContaining('7 days'), findsNothing);
  });

  testWidgets('assign mode: dropdown ng rider at "Assign quota" button',
      (tester) async {
    await pumpDialog(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Assign rider quota'), findsOneWidget);
    expect(find.text('Select a rider'), findsOneWidget);
    expect(find.text('Assign quota'), findsWidgets);
    // Daily ang default — isang araw lang.
    expect(find.textContaining('1 day'), findsOneWidget);
  });

  testWidgets('currency: comma habang nagta-type + live peso preview',
      (tester) async {
    await pumpDialog(tester, existing: _weeklyQuota());

    final amountField = find.byType(TextFormField).first;

    // Naka-group ang libo habang nagta-type.
    await tester.enterText(amountField, '2500000');
    await tester.pumpAndSettle();
    expect(find.text('2,500,000'), findsOneWidget);
    // Live preview sa tamang peso format.
    expect(find.text('Rider must collect ₱2,500,000.00'), findsOneWidget);

    // May decimal din.
    await tester.enterText(amountField, '2500.5');
    await tester.pumpAndSettle();
    expect(find.text('2,500.5'), findsOneWidget);
    expect(find.text('Rider must collect ₱2,500.50'), findsOneWidget);
  });

  testWidgets('invalid amount: error sa ilalim ng field, hindi nagsasara',
      (tester) async {
    await pumpDialog(tester, existing: _weeklyQuota());

    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a positive target amount'), findsOneWidget);
    expect(find.text('Edit rider quota'), findsOneWidget);
  });

  testWidgets('mobile width: walang overflow', (tester) async {
    await pumpDialog(tester, width: 400, existing: _weeklyQuota());

    expect(tester.takeException(), isNull);
    expect(find.text('Edit rider quota'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
  });
}
