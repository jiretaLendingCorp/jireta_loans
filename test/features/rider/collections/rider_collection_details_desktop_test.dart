// test/features/rider/collections/rider_collection_details_desktop_test.dart
//
// LAYOUT NG RIDER COLLECTION DETAILS SA DESKTOP
//
// DATI: isang column lang na nakaunat sa buong lapad — kalahati ng bawat card
// ay blangko, dumidikit ang value sa mahabang label ("Amount to
// Collect₱5,000.00"), at nauuwi sa ibaba ng viewport ang Accept/Decline bar.
//
// NGAYON:
//   • Accepted/in_progress: dalawang column — info sa KALIWA, collect form sa
//     KANAN, parehong may cap at nakasentro (hindi nakaunat sa 1366).
//   • Assigned: isang column na may cap, at buo (hindi putol) ang Accept /
//     Decline bar sa ilalim ng viewport.
//   • Ang label column ng info rows ay 140 (dating 110) — kasya ang
//     "Amount to Collect" bago magsimula ang halaga.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/data/datasources/remote/collection_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/models/collection_assignment_model.dart';
import 'package:jireta_loans/presentation/features/rider/collections/providers/rider_collection_provider.dart';
import 'package:jireta_loans/presentation/features/rider/collections/screens/rider_collection_details_screen.dart';

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

/// Assignment na may hininging ₱5,000 pero ₱200 lang ang installment due —
/// pareho ng totoong data sa screenshot ng rider.
CollectionAssignmentModel _assignment(String status) =>
    CollectionAssignmentModel.fromJson({
      'id': 'c1',
      'loan_schedule_id': 's1',
      'status': status,
      'collection_type': 'rider',
      'requested_amount': 5000,
      'collection_schedule': '2026-10-21T12:00:00+08:00',
      'created_at': '2026-10-21T08:00:00.000Z',
      'loan_schedule': {
        'id': 's1',
        'amount_due': 200,
        'due_date': '2026-09-27',
        'period_number': 6,
        'loan': {
          'loan_number': 'LN-2026-605277',
          'lender_profiles': {
            'users': {
              'first_name': 'PrinCess',
              'last_name': 'Armalyn',
              'phone_number': '09156882724',
            },
          },
        },
      },
    });

class _StubCollectionNotifier extends RiderCollectionNotifier {
  _StubCollectionNotifier(CollectionAssignmentModel col, Ref ref)
      : super(CollectionRemoteDataSource(DioClientFake()), ref) {
    state = RiderCollectionState(selectedCollection: col);
  }

  @override
  Future<void> load({String? status, bool silent = false}) async {}

  @override
  Future<void> loadDetails(String assignmentId, {bool silent = false}) async {}
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
    CollectionAssignmentModel col, {
    Size size = const Size(1366, 768),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/rider/collections/c1',
      routes: [
        GoRoute(
          path: '/rider/collections/c1',
          builder: (_, __) =>
              const RiderCollectionDetailsScreen(collectionId: 'c1'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        riderCollectionProvider
            .overrideWith((ref) => _StubCollectionNotifier(col, ref)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('desktop accepted: magkatabi ang info at ang collect form',
      (tester) async {
    await pumpDetails(tester, _assignment('accepted'));

    expect(tester.takeException(), isNull);
    expect(find.text('Lender Information'), findsOneWidget);
    expect(find.text('Collection Details'), findsOneWidget);

    final info = tester.getTopLeft(find.text('Lender Information'));
    final form = tester.getTopLeft(find.text('Collection Details'));

    // Dalawang column: nasa KANAN ng info card ang collect form.
    expect(form.dx, greaterThan(info.dx + 200),
        reason: 'Dapat magkatabi (hindi naka-stack) ang dalawang column');
    // Pareho ang taas ng simula — magkatapat ang dalawang column.
    expect((form.dy - info.dy).abs(), lessThan(120));

    // May cap ang content: hindi umaabot sa kanang gilid ng 1366 na viewport.
    final rightEdge = tester.getRect(find.text('Collection Details')).right;
    expect(rightEdge, lessThan(1366 - 100),
        reason: 'Dapat may cap at nakasentro ang content sa desktop');
  });

  testWidgets('desktop accepted: maluwag ang label column (140)',
      (tester) async {
    await pumpDetails(tester, _assignment('accepted'));

    expect(find.text('Amount to Collect'), findsOneWidget);
    expect(find.text('Installment Due'), findsOneWidget);
    expect(find.text('₱200.00'), findsWidgets);

    final label = tester.getRect(find.text('Amount to Collect'));
    final value = tester.getRect(find.text('₱5,000.00').first);

    // Dating 110 lang ang label column: "Amount to Collect₱5,000.00".
    // Ngayon 140 — kasya na ang buong label bago magsimula ang halaga.
    expect(label.width, greaterThanOrEqualTo(140));
    expect(value.left - label.left, greaterThanOrEqualTo(140),
        reason: 'Dapat magsimula ang halaga pagkatapos ng label column');
  });

  testWidgets('desktop assigned: buo ang Accept/Decline bar sa viewport',
      (tester) async {
    await pumpDetails(tester, _assignment('assigned'));

    expect(tester.takeException(), isNull);

    final accept =
        tester.getRect(find.widgetWithText(ElevatedButton, 'Accept'));
    final decline =
        tester.getRect(find.widgetWithText(OutlinedButton, 'Decline'));

    // Dating nahahati/putol sa ilalim ng viewport.
    expect(accept.bottom, lessThanOrEqualTo(768),
        reason: 'Dapat buo ang Accept button sa loob ng viewport');
    expect(decline.bottom, lessThanOrEqualTo(768),
        reason: 'Dapat buo ang Decline button sa loob ng viewport');
    expect(accept.top, greaterThan(500),
        reason: 'Dapat naka-pin sa ibaba ang action bar');
  });

  testWidgets('mobile: naka-stack pa rin at walang desktop cap',
      (tester) async {
    await pumpDetails(tester, _assignment('accepted'),
        size: const Size(390, 844));

    expect(tester.takeException(), isNull);

    final info = tester.getCenter(find.text('Lender Information'));
    final form = tester.getCenter(find.text('Collection Details'));
    expect(form.dy, greaterThan(info.dy + 100),
        reason: 'Naka-stack dapat ang mga card sa mobile');
  });
}
