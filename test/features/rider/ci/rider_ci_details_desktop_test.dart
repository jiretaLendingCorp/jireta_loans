// test/features/rider/ci/rider_ci_details_desktop_test.dart
//
// LAYOUT NG RIDER CI DETAILS SA DESKTOP
//
// DATI: custom na `Scaffold` lang ang CI wizard kahit sa desktop — nawawala ang
// rider side nav bar at punong-puno ng page ang AppBar, kaya walang paraan para
// lumipat ng pahina maliban sa back button. Naka-stretch din ang 1 → 2 → 3
// pipeline sa buong 1366px kaya magkahiwalay nang todo ang mga step.
//
// NGAYON:
//   • Desktop: `WebScaffold` (rider sidebar + top bar), kaya nananatili ang side
//     nav bar, at ang stepper ay naka-cap (760) at nakasentro.
//   • Mobile: hindi nagbago — mobile AppBar at walang sidebar.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/data/datasources/remote/ci_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/models/credit_investigation_model.dart';
import 'package:jireta_loans/presentation/features/rider/ci/providers/rider_ci_provider.dart';
import 'package:jireta_loans/presentation/features/rider/ci/screens/rider_ci_details_screen.dart';

import '../../../helpers/audit_test_helpers.dart';

class DioClientFake extends FakeDioClient {
  DioClientFake()
      : super((o) async => Response<dynamic>(
              requestOptions: o,
              data: {
                'data': <dynamic>[],
                'meta': {'unread_count': 0, 'total': 0},
              },
            ));
}

CreditInvestigationModel _ci(String status) => CreditInvestigationModel(
      id: 'ci1',
      loanId: 'l1',
      status: status,
      createdAt: DateTime(2026, 10, 21, 8, 30),
      investigationNotes: 'Verify borrower address and employment.',
      loan: {
        'loan_number': 'LN-2026-916379',
        'lender_address': 'Pedro, Esperanza, Dilasag, Aurora',
        'lender_profile': {
          'users': {
            'first_name': 'Mike',
            'last_name': 'Nindo',
            'phone_number': '09748547545',
          },
        },
      },
      assignedByUser: {'first_name': 'Myline', 'last_name': 'Cayabyab'},
    );

class _StubCiNotifier extends RiderCiNotifier {
  _StubCiNotifier(CreditInvestigationModel ci, Ref ref)
      : super(CiRemoteDataSource(DioClientFake()), ref) {
    state = RiderCiState(selectedCi: ci);
  }

  @override
  Future<void> load({String? status, bool silent = false}) async {}

  @override
  Future<void> loadDetails(String ciId, {bool silent = false}) async {}
}

void main() {
  setUpAll(() async {
    await loadTestEnv();
  });

  setUp(() {
    GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
        () => NotificationRemoteDataSource(DioClientFake()));
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pumpDetails(
    WidgetTester tester,
    CreditInvestigationModel ci, {
    Size size = const Size(1366, 768),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/rider/ci/ci1',
      routes: [
        GoRoute(
          path: '/rider/ci/ci1',
          builder: (_, __) => const RiderCiDetailsScreen(ciId: 'ci1'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        riderCiProvider.overrideWith((ref) => _StubCiNotifier(ci, ref)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('desktop: may side nav bar (hindi ito nawawala sa wizard)',
      (tester) async {
    await pumpDetails(tester, _ci('assigned'));

    expect(tester.takeException(), isNull);

    // Rider sidebar items.
    expect(find.text('CI Tasks'), findsOneWidget);
    expect(find.text('Collections'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);

    // Desktop chrome — walang mobile AppBar.
    expect(find.byType(AppBar), findsNothing);
    // Nasa top bar ng shell ang title.
    expect(find.text('CI Investigation'), findsOneWidget);
    expect(find.text('Lender Information'), findsOneWidget);
  });

  testWidgets('desktop: naka-cap at nakasentro ang 1, 2, 3 na stepper',
      (tester) async {
    await pumpDetails(tester, _ci('in_progress'));

    expect(tester.takeException(), isNull);

    final details = tester.getCenter(find.text('Details'));
    final upload = tester.getCenter(find.text('Upload'));
    final review = tester.getCenter(find.text('Review'));

    // Magkakasunod at pantay ang agwat — hindi nakaunat sa 1366px.
    expect(upload.dx, greaterThan(details.dx));
    expect(review.dx, greaterThan(upload.dx));
    expect(review.dx - details.dx, lessThan(620),
        reason: 'Dapat naka-cap (900) ang pipeline, hindi 1366 ang lapad');
    // Nasa loob ng content area (may sidebar sa kaliwa) at hindi dumidikit sa
    // kanang gilid ng viewport.
    expect(details.dx, greaterThan(240));
    expect(review.dx, lessThan(1366 - 200));

    // Pantay ang pipeline sa action bar — iisang naka-cap na column (900).
    // Ang Continue button ay nasa kanang kalahati ng action bar, kaya ang
    // right edge nito ang hangganan ng column (16px padding).
    final cont =
        tester.getRect(find.widgetWithText(ElevatedButton, 'Continue'));
    expect(cont.right, lessThan(1366 - 100),
        reason: 'Dapat may cap din ang action bar, hindi buong viewport');
    // Nakasentro ang pipeline sa loob ng column.
    final columnCenter = cont.right + 16 - 900 / 2;
    expect(((details.dx + review.dx) / 2 - columnCenter).abs(), lessThan(16),
        reason: 'Dapat magkapantay ang gitna ng pipeline at ng column');
  });

  testWidgets('mobile: mobile AppBar pa rin at walang sidebar',
      (tester) async {
    await pumpDetails(tester, _ci('assigned'), size: const Size(390, 844));

    expect(tester.takeException(), isNull);

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('CI Tasks'), findsNothing);
    expect(find.text('CI Investigation'), findsOneWidget);
  });
}
