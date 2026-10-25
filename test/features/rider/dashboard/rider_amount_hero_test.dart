// test/features/rider/dashboard/rider_amount_hero_test.dart
//
// TOTAL COLLECTED CARD — quota sa LOOB, walang sariling card/linya
//
//   * Ang quota (hal. weekly) ay nasa LOOB ng berdong Total Collected card at
//     nasa TAAS ng nakolektang halaga — hindi na hiwalay na card sa ibaba.
//   * WALANG sariling card background/border ang quota strip (dating puting
//     translucent na panel) at WALANG separating line sa pagitan nito at ng
//     "TOTAL COLLECTED".
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/theme/app_colors.dart';
import 'package:jireta_loans/data/datasources/remote/collection_remote_datasource.dart';
import 'package:jireta_loans/data/models/kpi_rider_model.dart';
import 'package:jireta_loans/data/models/rider_quota_model.dart';
import 'package:jireta_loans/presentation/features/rider/dashboard/providers/rider_dashboard_provider.dart';
import 'package:jireta_loans/presentation/features/rider/dashboard/screens/widgets/rider_amount_hero.dart';
import 'package:jireta_loans/presentation/features/rider/quota/providers/rider_quota_provider.dart';

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

RiderQuotaSelf _weeklyQuota() => RiderQuotaSelf(
      current: RiderQuota.fromJson({
        'quota_id': 'q1',
        'rider_id': 'r1',
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
      }),
    );

class _StubQuotaNotifier extends RiderQuotaNotifier {
  _StubQuotaNotifier(RiderQuotaSelf self)
      : super(CollectionRemoteDataSource(_OfflineDio())) {
    state = RiderQuotaState(data: self);
  }

  @override
  Future<void> load({bool silent = false}) async {}
}

void main() {
  setUpAll(() async {
    await loadTestEnv();
  });

  Future<void> pumpHero(WidgetTester tester,
      {double width = 800, KpiRiderModel? kpi}) async {
    tester.view.physicalSize = Size(width, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          riderQuotaProvider
              .overrideWith((ref) => _StubQuotaNotifier(_weeklyQuota())),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(18),
              child: RiderAmountHero(
                state: RiderDashboardState(kpi: kpi ?? KpiRiderModel.empty()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Ang berdong hero card (gradient na may riderGreen).
  Finder heroCard() => find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        if (d is! BoxDecoration || d.gradient is! LinearGradient) return false;
        return (d.gradient as LinearGradient)
            .colors
            .contains(AppColors.riderGreen);
      });

  testWidgets('quota ay nasa loob ng Total Collected card, sa taas ng halaga',
      (tester) async {
    await pumpHero(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('WEEKLY QUOTA'), findsOneWidget);
    expect(find.text('5.0%'), findsOneWidget);
    expect(find.text('₱5,000.00 of ₱100,000.00'), findsOneWidget);
    expect(find.text('TOTAL COLLECTED'), findsOneWidget);

    // Nasa taas ng amount: mas mababa ang TOTAL COLLECTED header.
    final quota = tester.getRect(find.text('WEEKLY QUOTA'));
    final total = tester.getRect(find.text('TOTAL COLLECTED'));
    expect(quota.bottom, lessThan(total.top));

    // Bahagi ng hero card — hindi lumalabas sa card.
    final hero = tester.getRect(heroCard());
    expect(hero.contains(quota.center), isTrue);
    expect(hero.contains(total.center), isTrue);
  });

  testWidgets('walang sariling card background ang quota strip',
      (tester) async {
    await pumpHero(tester);

    // Isang decorated Container lang ang ancestor ng quota label — ang hero
    // card mismo. Dati may pangalawang translucent na panel dito.
    final decoratedAncestors = tester
        .widgetList<Container>(find.ancestor(
          of: find.text('WEEKLY QUOTA'),
          matching: find.byType(Container),
        ))
        .where((c) => c.decoration != null)
        .length;
    expect(decoratedAncestors, 1);
  });

  testWidgets('walang "failed" chip sa Total Collected card', (tester) async {
    // Ang mga failed collection ay nasa History, hindi sa dashboard hero.
    await pumpHero(tester,
        kpi: const KpiRiderModel(
            totalFailedCollections: 3, totalAmountCollected: 5000));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('failed'), findsNothing);
    expect(find.text('₱5,000.00'), findsOneWidget);
  });

  testWidgets('walang separating line sa pagitan ng quota at TOTAL COLLECTED',
      (tester) async {
    await pumpHero(tester);

    // 8px (bar gap) + 5px bar + 14px SizedBox lang — walang dagdag na linya.
    final bar = tester.getRect(find.byType(LinearProgressIndicator));
    final total = tester.getRect(find.text('TOTAL COLLECTED'));
    expect(total.top - bar.bottom, lessThan(20));
  });
}
