// test/features/employee/rider_monitoring/emp_rider_monitoring_test.dart
//
// RIDER MONITORING SA EMPLOYEE ROLE
//
// Dati HM-only ang Rider Monitoring (`/hm/rider-monitoring`) kahit ang
// backend (`collections-view?fn=rider-monitoring`) ay tumatanggap na ng
// HM **at** EMPLOYEE. Sinusuri dito:
//   • may sariling employee routes (`/employee/rider-monitoring*`);
//   • "Rider Quotas" ang nasa employee sidebar (nakatago ang Monitoring);
//   • employee URL ang binubuksan ng View action (hindi tumatalon sa `/hm/...`);
//   • WALANG Quotas tab sa employee (HM-only ang pag-set ng quota).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/core/constants/route_constants.dart';
import 'package:jireta_loans/data/models/rider_collection_monitoring_model.dart';
import 'package:jireta_loans/data/models/rider_quota_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_quotas/providers/hm_rider_quotas_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_quotas/screens/hm_rider_quotas_screen.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_monitoring/providers/hm_rider_monitoring_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_monitoring/screens/hm_rider_monitoring_screen.dart';
import 'package:jireta_loans/presentation/features/head_manager/rider_monitoring/widgets/rider_monitoring_section_tabs.dart';

const _row = RiderMonitoringRow(
  riderId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  riderName: 'Anthony Maramba',
  phoneNumber: '09635267491',
  plateNumber: 'PRT-6817',
  assignedAccounts: 4,
  assignedInstallments: 6,
  expectedCollection: 12000,
  confirmedCollection: 7500.5,
  remainingDue: 4499.5,
  overdueAccounts: 2,
  lastActivityAt: null,
  collectionPerformance: 62.5,
);

const _state = HmRiderMonitoringState(rows: [_row], total: 1);

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// Pump ang table sa loob ng router na may parehong HM at employee detail
/// routes, para makita kung alin ang binubuksan ng View action.
Future<void> _pumpTable(
  WidgetTester tester, {
  String? detailsRoute,
  bool widgetDefault = false,
}) async {
  tester.view.physicalSize = const Size(1366, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: RouteConstants.empRiderMonitoring,
    routes: [
      GoRoute(
        path: RouteConstants.empRiderMonitoring,
        builder: (_, __) => Scaffold(
          body: Center(
            child: SizedBox(
              width: 1062,
              height: 420,
              child: widgetDefault
                  // Walang `detailsRoute` → sariling default ng table (HM).
                  ? const RiderMonitoringTable(state: _state)
                  : RiderMonitoringTable(
                      state: _state,
                      detailsRoute: detailsRoute ??
                          RouteConstants.empRiderMonitoringDetails,
                    ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: RouteConstants.empRiderMonitoringDetails,
        builder: (_, s) =>
            Scaffold(body: Text('EMP ${s.pathParameters['id']}')),
      ),
      GoRoute(
        path: RouteConstants.hmRiderMonitoringDetails,
        builder: (_, s) => Scaffold(body: Text('HM ${s.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

void main() {
  group('Employee rider monitoring — routes at nav', () {
    test('may sariling employee route constants (monitoring, details, quotas)',
        () {
      final routes = _read('lib/core/constants/route_constants.dart');
      expect(routes,
          contains("empRiderMonitoring = '/employee/rider-monitoring'"));
      expect(
          routes,
          contains(
              "empRiderMonitoringDetails =\n      '/employee/rider-monitoring/:id'"));
      expect(
          routes,
          contains(
              "empRiderMonitoringQuotas =\n      '/employee/rider-monitoring/quotas'"));
    });

    test('naka-register ang employee routes kasama ang read-only quotas', () {
      final router = _read('lib/core/router/app_router.dart');
      expect(router, contains('RouteConstants.empRiderMonitoring,'));
      expect(router, contains('RouteConstants.empRiderMonitoringDetails,'));
      expect(router, contains('RouteConstants.empRiderMonitoringQuotas,'));
      // Quotas ng employee: read-only (HM lang ang pwedeng mag-manage).
      expect(
        RegExp(r'RouteConstants\.empRiderMonitoringQuotas,[\s\S]{0,300}?canManage: false')
            .hasMatch(router),
        isTrue,
        reason: 'Walang `canManage: false` sa employee quotas route',
      );
      // Naka-register BAGO ang quotas bago ang `:id` route.
      expect(
        router.indexOf('RouteConstants.empRiderMonitoringQuotas\n'),
        lessThan(
            router.indexOf('path: RouteConstants.empRiderMonitoringDetails')),
        reason: 'Mauuna dapat ang /quotas sa /:id para hindi ito rider id',
      );
      // Nakatago ang Monitoring — ang base route ay redirect sa Quotas.
      final empBase =
          router.indexOf('path: RouteConstants.empRiderMonitoring,');
      expect(empBase, greaterThan(-1));
      expect(
        router.substring(empBase, empBase + 200),
        contains(
            'redirect: (ctx, s) => RouteConstants.empRiderMonitoringQuotas'),
        reason: 'Dapat Quotas ang buksan ng /employee/rider-monitoring',
      );
    });

    test('nasa employee sidebar ang Rider Quotas', () {
      final sidebar =
          _read('lib/presentation/shared/widgets/layout/web_scaffold.dart');
      final empItems =
          sidebar.substring(sidebar.indexOf('List<_NavItem> _empItems()'));
      expect(empItems, contains("'Rider Quotas'"));
      expect(empItems, isNot(contains("'Rider Monitoring'")));
      expect(empItems, contains('RouteConstants.empRiderMonitoringQuotas'));
    });
  });

  group('Employee rider monitoring — UI', () {
    testWidgets('View action ay pumupunta sa employee details route',
        (tester) async {
      await _pumpTable(tester,
          detailsRoute: RouteConstants.empRiderMonitoringDetails);

      await tester
          .tap(find.byTooltip('View rider details & collection history').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('EMP '), findsOneWidget,
          reason: 'Dapat employee URL ang binuksan, hindi /hm/...');
      expect(find.textContaining('HM '), findsNothing);
    });

    testWidgets('default (HM) ay HM details route pa rin', (tester) async {
      await _pumpTable(tester, widgetDefault: true);
      await tester
          .tap(find.byTooltip('View rider details & collection history').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('HM '), findsOneWidget);
      expect(find.textContaining('EMP '), findsNothing);
    });

    testWidgets('nakatago ang Monitoring tab, Quotas ang natitira',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: RiderMonitoringSectionTabs(
            activeRoute: RouteConstants.empRiderMonitoringQuotas,
            monitoringRoute: RouteConstants.empRiderMonitoring,
            quotasRoute: RouteConstants.empRiderMonitoringQuotas,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Nakatago ang Monitoring tab pero buo pa rin ang Quotas tab.
      expect(find.text('Monitoring'), findsNothing);
      expect(find.text('Quotas'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('read-only na quota table: walang edit/close, lock lang',
        (tester) async {
      const quota = RiderQuota(
        quotaId: 'q1',
        riderId: 'r1',
        riderName: 'Anthony Maramba',
        period: 'daily',
        targetAmount: 5000,
        confirmedCollection: 1200,
        remainingTarget: 3800,
        completionPercentage: 24,
        status: 'active',
      );

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1062,
              height: 320,
              child: RiderQuotaTable(
                state: HmRiderQuotasState(rows: [quota], total: 1),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.edit_outlined), findsNothing,
          reason: 'Walang edit action dapat sa employee');
      expect(find.byTooltip('Close quota'), findsNothing);
      expect(find.byIcon(Icons.lock_clock_outlined), findsOneWidget);
    });

    testWidgets('nakatago rin ang Monitoring tab sa HM', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: RiderMonitoringSectionTabs(
            activeRoute: RouteConstants.hmRiderMonitoringQuotas,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Monitoring'), findsNothing);
      expect(find.text('Quotas'), findsOneWidget);
    });
  });
}
