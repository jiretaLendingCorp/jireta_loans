// test/features/head_manager/dashboard/hm_dashboard_layout_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jireta_loans/data/datasources/remote/auth_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/kpi_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/data/models/kpi_head_manager_model.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/dashboard/providers/hm_dashboard_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/dashboard/screens/hm_dashboard_screen.dart';
import 'package:jireta_loans/presentation/features/head_manager/dashboard/widgets/hm_analytics_panel.dart';
import 'package:jireta_loans/presentation/features/head_manager/profile/providers/hm_profile_provider.dart';

import '../../../helpers/audit_test_helpers.dart';

KpiHeadManagerModel buildKpi() => const KpiHeadManagerModel(
      totalEmployees: 12,
      totalRiders: 8,
      totalLenders: 340,
      totalLoanApplications: 95,
      totalApprovedLoans: 60,
      totalRejectedLoans: 15,
      totalActiveLoans: 42,
      totalCompletedLoans: 31,
      totalOverdueLoans: 4,
      totalLoanAmountReleased: 2450000.50,
      totalAmountCollected: 1832000.75,
      totalOutstandingBalance: 620000.25,
      totalInterestEarned: 312000.40,
      totalPenaltiesCollected: 8400.60,
      totalRevenue: 320400,
      totalCollectionTransactions: 58,
      totalCiAssignments: 9,
      totalReportExports: 22,
      totalPendingAccountUpgrade: 3,
      monthlySeries: [
        MonthlyKpiPoint(month: '2026-03', applications: 12, released: 300000, collected: 240000),
        MonthlyKpiPoint(month: '2026-04', applications: 18, released: 450000, collected: 380000),
        MonthlyKpiPoint(month: '2026-05', applications: 9, released: 220000, collected: 190000),
        MonthlyKpiPoint(month: '2026-06', applications: 21, released: 520000, collected: 410000),
        MonthlyKpiPoint(month: '2026-07', applications: 15, released: 400000, collected: 330000),
        MonthlyKpiPoint(month: '2026-08', applications: 20, released: 560000, collected: 280000),
      ],
    );

class FakeKpiDS extends KpiRemoteDataSource {
  FakeKpiDS()
      : super(FakeDioClient((_) async => throw UnimplementedError()));

  @override
  Future<KpiHeadManagerModel> getHeadManagerKpi({String? month}) async => buildKpi();
}

class FakeDashboardNotifier extends HmDashboardNotifier {
  FakeDashboardNotifier() : super(FakeKpiDS());

  @override
  Future<void> loadKpis({String? month, bool silent = false}) async {
    state = HmDashboardState(kpi: buildKpi());
  }
}

class FakeUserDS extends UserRemoteDataSource {
  FakeUserDS()
      : super(FakeDioClient((_) async => throw UnimplementedError()));

  @override
  Future<UserModel> getProfile({String? userId}) async {
    return UserModel(
      id: 'hm-1',
      role: 'head_manager',
      firstName: 'Ana',
      lastName: 'Doe',
      accountStatus: 'active',
      forcePasswordChange: false,
      createdAt: DateTime.now(),
    );
  }
}

class FakeAuthDS extends AuthRemoteDataSource {
  FakeAuthDS()
      : super(FakeDioClient((_) async => throw UnimplementedError()));
}

class FakeProfileNotifier extends HmProfileNotifier {
  FakeProfileNotifier() : super(FakeUserDS(), FakeAuthDS());

  @override
  Future<void> loadProfile({bool silent = false}) async {
    state = HmProfileState(user: UserModel(
      id: 'hm-1',
      role: 'head_manager',
      firstName: 'Ana',
      lastName: 'Doe',
      accountStatus: 'active',
      forcePasswordChange: false,
      createdAt: DateTime.now(),
    ));
  }
}

Future<void> pumpPanel(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: HmAnalyticsPanel(kpi: buildKpi()),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> pumpDashboard(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final details = <FlutterErrorDetails>[];
  final oldOnError = FlutterError.onError;
  FlutterError.onError = (d) {
    details.add(d);
    debugPrint('DETAILS: ${d.exception}\n${d.stack}');
  };
  addTearDown(() => FlutterError.onError = oldOnError);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      hmDashboardProvider.overrideWith((ref, _) => FakeDashboardNotifier()),
      hmProfileProvider.overrideWith((ref) => FakeProfileNotifier()),
    ],
    child: const MaterialApp(home: HmDashboardScreen()),
  ));
  await tester.pumpAndSettle();
  if (details.isNotEmpty) {
    fail('Pump threw: ${details.map((d) => d.exception).toList()}');
  }
}

void main() {
  group('HmAnalyticsPanel', () {
    for (final width in [1280.0, 1024.0, 800.0, 600.0, 420.0, 360.0]) {
      testWidgets('no overflow at width $width', (tester) async {
        await pumpPanel(tester, width);
        expect(tester.takeException(), isNull,
            reason: 'Overflow rendered at width $width');
      });
    }
  });

  group('HmDashboardScreen', () {
    for (final width in [1280.0, 1024.0, 800.0, 600.0, 420.0, 360.0]) {
      testWidgets('no overflow at width $width', (tester) async {
        await pumpDashboard(tester, width);
        expect(tester.takeException(), isNull,
            reason: 'Overflow rendered at width $width');
      });
    }
  });
}