// test/rider_collection_proof_desktop_layout_test.dart
//
// STEP 2 (PROOF) AT STEP 3 (REVIEW) DESKTOP LAYOUT — /rider/collections/:id
//
//   * Step 2 desktop: DALAWANG column — Payment Proof sa kaliwa, Lender
//     Signature sa kanan — at naka-cap (1080) at nakasentro ang buong hakbang.
//   * Step 3 desktop: DALAWANG column — Lender & Loan sa kaliwa, Collection
//     Details sa kanan — naka-cap (1080), at naka-align sa kanan ang
//     Back + Submit.
//   * Mobile: isang column pa rin (hindi binago).
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

/// Umiiral na koleksyon na na-accept na at may na-record nang amount — kaya
/// bukas ang Proof at Review steps (hindi lalabas ang "go to Collect" lock).
CollectionAssignmentModel _inProgressCollection() =>
    CollectionAssignmentModel.fromJson({
      'id': 'abc',
      'loan_schedule_id': 'sched-1',
      'status': 'in_progress',
      'amount_collected': 3200,
      'collection_schedule': '2026-09-28T02:40:00+08:00',
      'lender_name': 'Shin Jay Lomibao',
      'loan_number': 'LN-2026-446486',
    });

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
      _inProgressCollection();

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
      [_inProgressCollection()];
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

  Future<void> pumpScreen(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
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

  /// Lumipat ng wizard step gamit ang TabBarView controller (kapareho ng
  /// ginagawa ng Next button, pero hindi kailangan ng photo para sa Step 3).
  Future<void> goToStep(WidgetTester tester, int index) async {
    final tabView = tester.widget<TabBarView>(find.byType(TabBarView));
    tabView.controller!.animateTo(index);
    await tester.pumpAndSettle();
  }

  /// Pumunta sa Step 2 (Proof) sa paraang ginagamit ng rider: tap sa Next.
  Future<void> pumpProofStep(WidgetTester tester, double width) async {
    await pumpScreen(tester, width);

    final next = find.text('Next');
    await tester.ensureVisible(next);
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();
  }

  group('Rider collection Proof step', () {
    testWidgets('desktop: dalawang column at naka-cap ang lapad',
        (tester) async {
      await pumpProofStep(tester, 1400);

      expect(tester.takeException(), isNull);
      expect(find.text('Payment Proof'), findsOneWidget);
      expect(find.text('Lender Signature (optional)'), findsOneWidget);

      final proof = tester.getRect(find.text('Payment Proof'));
      final signature = tester.getRect(find.text('Lender Signature (optional)'));

      // Magkatabi: pareho ang row, nasa KANAN ang signature card.
      expect((signature.top - proof.top).abs(), lessThan(2));
      expect(signature.left, greaterThan(proof.right));

      // Naka-cap (1080) at nakasentro ang content — hindi nakaunat sa buong
      // lapad ng desktop body.
      final cap = find
          .byWidgetPredicate((w) =>
              w is ConstrainedBox && w.constraints.maxWidth == 1080)
          .first;
      final capWidth = tester.getRect(cap).width;
      expect(capWidth, lessThanOrEqualTo(1080));
      expect(capWidth, greaterThan(600));
    });

    testWidgets('mobile: isang column pa rin', (tester) async {
      await pumpProofStep(tester, 390);

      expect(tester.takeException(), isNull);
      final proof = tester.getRect(find.text('Payment Proof'));
      final signature = tester.getRect(find.text('Lender Signature (optional)'));

      expect(signature.top, greaterThan(proof.bottom));
    });
  });

  group('Rider collection Review step', () {
    testWidgets('desktop: dalawang column, naka-cap, at right-aligned actions',
        (tester) async {
      await pumpScreen(tester, 1400);
      await goToStep(tester, 2);

      expect(tester.takeException(), isNull);
      expect(find.text('Lender & Loan'), findsOneWidget);
      expect(find.text('Collection Details'), findsOneWidget);
      // Hindi na isang mahabang card ang buong review sa desktop.
      expect(find.text('Review Details'), findsNothing);

      final lenderCard = tester.getRect(find.text('Lender & Loan'));
      final collectionCard = tester.getRect(find.text('Collection Details'));

      expect((collectionCard.top - lenderCard.top).abs(), lessThan(2));
      expect(collectionCard.left, greaterThan(lenderCard.right));

      final cap = find
          .byWidgetPredicate((w) =>
              w is ConstrainedBox && w.constraints.maxWidth == 1080)
          .first;
      final capRect = tester.getRect(cap);
      expect(capRect.width, lessThanOrEqualTo(1080));

      // Back + Submit: makitid lang at nakadikit sa KANANG gilid ng content
      // (hindi nakaunat sa buong lapad).
      final submit = tester.getRect(find.text('Submit'));
      expect(submit.width, lessThan(380));
      expect(capRect.right - submit.left, lessThan(380));
    });

    testWidgets('mobile: isang card pa rin', (tester) async {
      await pumpScreen(tester, 390);
      await goToStep(tester, 2);

      expect(tester.takeException(), isNull);
      expect(find.text('Review Details'), findsOneWidget);
      expect(find.text('Lender & Loan'), findsNothing);
      expect(find.text('Collection Details'), findsNothing);
    });
  });
}
