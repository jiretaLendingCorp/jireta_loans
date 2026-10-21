// test/features/rider/notifications/rider_notification_bell_test.dart
//
// REGRESSION: "walang nagnonotify sa rider"
//
// Ang bell dropdown (`NotificationDropdownPanel`) ay may branch lang para sa
// head manager, employee, at lender — WALA para sa rider. Kaya kahit may
// notifications ang rider (hal. bagong Cash on Delivery collection task),
// laging "You're all caught up" ang panel at 0 ang badge. Wala rin sa
// "View All Notifications" ang rider route.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/models/notification_model.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/features/rider/notifications/providers/rider_notification_provider.dart';
import 'package:jireta_loans/presentation/shared/providers/auth_state_provider.dart';
import 'package:jireta_loans/presentation/shared/widgets/notification_dropdown.dart';

import '../../../helpers/audit_test_helpers.dart';

UserModel _rider() => UserModel(
      id: 'rider-1',
      role: 'rider',
      firstName: 'PrinCess',
      lastName: 'Armalyn',
      accountStatus: 'active',
      forcePasswordChange: false,
      createdAt: DateTime.now(),
    );

class _FakeAuthNotifier extends AuthStateNotifier {
  _FakeAuthNotifier() {
    state = AuthState(isAuthenticated: true, user: _rider());
  }
}

class _OfflineDio extends FakeDioClient {
  _OfflineDio()
      : super((o) async => Response<dynamic>(
              requestOptions: o,
              data: {
                'data': <dynamic>[],
                'unread_count': 0,
                'meta': {'total': 0, 'total_pages': 1},
              },
            ));
}

NotificationModel _notification({
  required String id,
  required String title,
  required String body,
  bool isRead = false,
}) =>
    NotificationModel(
      id: id,
      userId: 'rider-1',
      title: title,
      body: body,
      type: 'collection_assigned',
      referenceId: 'c1',
      isRead: isRead,
      createdAt: DateTime.now(),
    );

class _StubRiderNotifications extends RiderNotificationNotifier {
  _StubRiderNotifications(List<NotificationModel> items)
      : super(NotificationRemoteDataSource(_OfflineDio())) {
    state = RiderNotificationState(
      notifications: items,
      unreadCount: items.where((n) => !n.isRead).length,
    );
  }

  @override
  Future<void> load({bool silent = false}) async {}
}

Future<void> _pumpBell(
  WidgetTester tester,
  List<NotificationModel> items,
) async {
  tester.view.physicalSize = const Size(1366, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/rider/dashboard',
    routes: [
      GoRoute(
        path: '/rider/dashboard',
        builder: (_, __) => const Scaffold(
          body: Center(child: NotificationBellButton()),
        ),
      ),
      GoRoute(
        path: '/rider/notifications',
        builder: (_, __) => const Scaffold(body: Text('rider notifications page')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      authStateProvider.overrideWith((ref) => _FakeAuthNotifier()),
      riderNotificationProvider
          .overrideWith((ref) => _StubRiderNotifications(items)),
    ],
    child: MaterialApp.router(
      // Tunay na Inter ang gamitin — ang default test font ay sobrang lapad,
      // kaya nagmumukhang overflow ang header ng 360px na panel.
      theme: ThemeData(useMaterial3: true, fontFamily: 'Inter'),
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _loadInterFont() async {
  final loader = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes =
        File('assets/fonts/Inter/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await loadTestEnv();
    await _loadInterFont();
  });

  testWidgets('rider: may badge at laman ang bell dropdown', (tester) async {
    await _pumpBell(tester, [
      _notification(
        id: 'n1',
        title: 'New Cash on Delivery Collection Task',
        body: 'Hello! You have a new Cash on Delivery collection task.',
      ),
      _notification(
        id: 'n2',
        title: 'Collection Approved',
        body: 'Your collection was approved and verified.',
        isRead: true,
      ),
    ]);

    // Unread badge — dati laging 0 para sa rider.
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(find.text('New Cash on Delivery Collection Task'), findsOneWidget);
    expect(find.text('Collection Approved'), findsOneWidget);
    expect(find.text("You're all caught up"), findsNothing);

    // Rider icons: scooter para sa collection notifications — hindi van
    // (`local_shipping`).
    expect(find.byIcon(Icons.delivery_dining_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.local_shipping_outlined), findsNothing);
  });

  testWidgets('rider: tama ang relative time, hindi laging "Just now"',
      (tester) async {
    // Tunay na UTC instant na 5 minuto ang nakalipas — dumaan ito sa
    // `parseManila` sa loob ng model (+8h Manila wall time).
    final fiveMinAgoUtc = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 5))
        .toIso8601String();
    final n = NotificationModel.fromJson({
      'id': 'n1',
      'user_id': 'rider-1',
      'title': 'New Cash on Delivery Collection Task',
      'body': 'Hello! You have a new Cash on Delivery collection task.',
      'type': 'collection_assigned',
      'reference_id': 'c1',
      'is_read': false,
      'created_at': fiveMinAgoUtc,
    });

    await _pumpBell(tester, [n]);
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(find.text('5m ago'), findsOneWidget);
    expect(find.text('Just now'), findsNothing);
  });

  testWidgets('rider: buo ang body kahit mahaba — hindi pinutol ng 2 linya',
      (tester) async {
    const body = 'Hello! Your payment of ₱5,000 has been received. Your '
        'remaining balance is ₱5,800. Thank you for paying on time — '
        'keep it up!';
    await _pumpBell(tester, [
      _notification(id: 'n1', title: 'Payment Received', body: body),
    ]);

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    final paragraph = tester.renderObject<RenderParagraph>(find.text(body));
    expect(paragraph.didExceedMaxLines, isFalse,
        reason: 'Naputol ang body sa dropdown — hindi mabasa ang kabuuan');
    expect(tester.takeException(), isNull);
  });

  testWidgets('rider: "View All Notifications" papunta sa rider route',
      (tester) async {
    await _pumpBell(tester, [
      _notification(
        id: 'n1',
        title: 'New Cash on Delivery Collection Task',
        body: 'Hello! You have a new Cash on Delivery collection task.',
      ),
    ]);

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('View All Notifications'));
    await tester.pumpAndSettle();

    expect(find.text('rider notifications page'), findsOneWidget);
  });
}
