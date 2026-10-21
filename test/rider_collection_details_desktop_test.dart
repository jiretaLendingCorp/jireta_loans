// test/rider_collection_details_desktop_test.dart
//
// COMPLETED COLLECTION DETAILS (/rider/collections/:id mula sa History)
//
//   * Naka-center ang receipt sa max na lapad (1240) sa desktop — kapareho ng
//     rider dashboard/history/profile. Sa mobile, buong lapad pa rin.
//   * Wala nang \"Collection Proof\" section sa completed na detalye — tapos na
//     ang collection at naka-submit na ang proof.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:dio/dio.dart';

import 'package:jireta_loans/data/datasources/remote/collection_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/models/collection_assignment_model.dart';
import 'package:jireta_loans/presentation/features/rider/collections/providers/rider_collection_provider.dart';
import 'package:jireta_loans/presentation/features/rider/collections/screens/rider_collection_details_screen.dart';

import 'helpers/audit_test_helpers.dart';

CollectionAssignmentModel _completedCollection() =>
    CollectionAssignmentModel.fromJson({
      'id': 'abc',
      'loan_schedule_id': 'sched-1',
      'status': 'completed',
      'amount_collected': 70422,
      'completed_at': '2026-09-27T18:41:00+08:00',
      'collection_schedule': '2026-09-28T02:40:00+08:00',
      'lender_name': 'Shin Jay Lomibao',
      'loan_number': 'LN-2026-446486',
      'proof_photo': 'https://example.com/payment.jpg',
      'borrower_signature': 'https://example.com/signature.jpg',
    });

/// Walang network: laging ibinabalik ang naka-complete na collection.
class _StubCollectionDs extends CollectionRemoteDataSource {
  _StubCollectionDs()
      : super(FakeDioClient((o) async => Response<dynamic>(
            requestOptions: o,
            data: {
              'data': <dynamic>[],
              'meta': {'unread_count': 0, 'total': 0},
            },
          )));

  @override
  Future<CollectionAssignmentModel?> getCollectionById(String assignmentId) async =>
      _completedCollection();

  @override
  Future<List<CollectionAssignmentModel>> getCollectionList({
    String? status,
    String? riderId,
    String? dateFrom,
    String? dateTo,
    String? search,
    int page = 1,
    int limit = 20,
  }) async =>
      [_completedCollection()];
}

void main() {
  setUpAll(() async {
    await loadTestEnv();
  });

  setUp(() {
    GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
        () => NotificationRemoteDataSource(FakeDioClient((o) async => Response<dynamic>(
              requestOptions: o,
              data: {
                'data': <dynamic>[],
                'meta': {'unread_count': 0},
              },
            ))));
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pumpDetails(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ds = _StubCollectionDs();
    final router = GoRouter(
      initialLocation: '/rider/collections/abc',
      routes: [
        GoRoute(
          path: '/rider/collections/:id',
          builder: (_, state) =>
              RiderCollectionDetailsScreen(collectionId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        riderCollectionProvider
            .overrideWith((ref) => RiderCollectionNotifier(ds, ref)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('Rider completed collection details', () {
    testWidgets(
        'desktop: dalawang column, naka-cap sa 1080, walang Collection Proof',
        (tester) async {
      await pumpDetails(tester, 1920);

      expect(tester.takeException(), isNull);
      expect(find.text('Collection Completed'), findsOneWidget);
      expect(find.text('Collection Proof'), findsNothing);
      expect(find.text('Payment Proof'), findsNothing);

      final capBox = find
          .byWidgetPredicate((w) =>
              w is ConstrainedBox && w.constraints.maxWidth == 1080)
          .first;
      final capRect = tester.getRect(capBox);
      expect(capRect.width, 1080);

      // Success receipt sa KALIWA, mga detalye sa KANAN — magkatabi.
      final success = tester.getRect(find.text('Collection Completed'));
      final lender = tester.getRect(find.text('Lender Information'));
      expect(lender.left, greaterThan(success.right));
      // Parehong row: nasa loob ng vertical span ng success card ang lender
      // title (hindi naka-stack sa ilalim nito).
      expect(lender.top, lessThan(success.bottom));
      expect(lender.top, greaterThan(success.top - 80));

      // Naka-cap din ang footer: 380px na Done button, nakadikit sa KANAN.
      final done = tester.getRect(find.byType(ElevatedButton));
      expect(done.width, 380);
      expect(capRect.right - done.right, lessThan(2));
    });

    testWidgets('mobile: isang column at buong lapad pa rin', (tester) async {
      await pumpDetails(tester, 390);

      expect(tester.takeException(), isNull);
      expect(find.text('Collection Completed'), findsOneWidget);
      expect(find.text('Collection Proof'), findsNothing);

      final contentBox = find
          .ancestor(
            of: find.text('Collection Completed'),
            matching: find.byType(ConstrainedBox),
          )
          .first;
      expect(tester.getRect(contentBox).width, lessThanOrEqualTo(390));

      // Naka-stack: nasa ibaba ng success card ang Lender Information.
      final success = tester.getRect(find.text('Collection Completed'));
      final lender = tester.getRect(find.text('Lender Information'));
      expect(lender.top, greaterThan(success.bottom));
    });
  });
}
