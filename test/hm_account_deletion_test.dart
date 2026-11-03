// test/hm_account_deletion_test.dart
//
// Head Manager → Account Deletion queue:
//   * pending requests show the requester + approve/reject actions
//   * approve requires an identity-verification checkbox
//   * reject requires a short reason
//   * status filters call the API with the right `status`
//   * route + sidebar entry are wired
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/data/datasources/remote/account_deletion_remote_datasource.dart';
import 'package:jireta_loans/data/models/account_deletion_request_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/account_deletion/providers/hm_account_deletion_provider.dart';
import 'package:jireta_loans/presentation/features/head_manager/account_deletion/screens/hm_account_deletion_screen.dart';

class _FakeAccountDeletionDataSource
    implements AccountDeletionRemoteDataSource {
  _FakeAccountDeletionDataSource(this.rows);

  final List<AccountDeletionRequestModel> rows;
  final List<String> requestedStatuses = [];
  final List<Map<String, String?>> processed = [];
  bool failList = false;

  @override
  Future<List<AccountDeletionRequestModel>> listRequests({
    String status = 'pending',
  }) async {
    requestedStatuses.add(status);
    if (failList) throw StateError('offline');
    if (status == 'all') return rows;
    return rows.where((row) => row.status == status).toList();
  }

  @override
  Future<Map<String, dynamic>> processRequest({
    required String requestId,
    required String action,
    String? notes,
  }) async {
    processed.add({
      'request_id': requestId,
      'action': action,
      'notes': notes,
    });
    return {'success': true};
  }

  @override
  Future<Map<String, dynamic>> requestDeletion({
    required String identifier,
    required String fullName,
    String? reason,
  }) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> deleteSelf({
    required String confirmation,
    String? reason,
  }) =>
      throw UnimplementedError();
}

AccountDeletionRequestModel _request({
  String id = 'req-1',
  String reference = 'DEL-ABC123',
  String? fullName = 'Ana Cruz',
  String status = 'pending',
}) {
  return AccountDeletionRequestModel(
    id: id,
    reference: reference,
    userId: 'user-1',
    role: 'lender',
    identifier: '09171234567',
    identifierType: 'phone',
    fullName: fullName,
    reason: 'I no longer use the app.',
    source: 'web',
    status: status,
    requestedAt: DateTime(2026, 10, 30, 9, 15),
    processedAt: status == 'pending' ? null : DateTime(2026, 10, 31, 8),
    notes: status == 'pending' ? null : 'Verified by phone call',
  );
}

Future<_FakeAccountDeletionDataSource> _pump(
  WidgetTester tester, {
  List<AccountDeletionRequestModel>? rows,
}) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final ds = _FakeAccountDeletionDataSource(rows ?? [_request()]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hmAccountDeletionProvider.overrideWith(
          (ref) => HmAccountDeletionNotifier(ds),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const Scaffold(body: HmAccountDeletionBody()),
      ),
    ),
  );
  // initState schedules load in a post-frame callback.
  await tester.pump();
  await tester.pumpAndSettle();
  return ds;
}

void main() {
  test('model: completed rows may have no name/identifier', () {
    final model = AccountDeletionRequestModel.fromJson({
      'id': 'req-2',
      'reference': 'DEL-XYZ',
      'full_name': null,
      'identifier': '',
      'identifier_type': 'email',
      'source': 'in_app',
      'status': 'completed',
      'requested_at': '2026-10-30T09:15:00Z',
    });

    expect(model.displayName, 'Deleted account');
    expect(model.identifier, isNull);
    expect(model.sourceLabel, 'In-app');
    expect(model.statusLabel, 'Completed');
    expect(model.roleLabel, 'Unknown');
    expect(model.isPending, isFalse);
  });

  testWidgets('pending request: requester, reference, at actions',
      (tester) async {
    await _pump(tester);

    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(find.text('DEL-ABC123'), findsOneWidget);
    // Filter chip + status chip sa card.
    expect(find.text('Pending'), findsWidgets);
    expect(find.text('Lendee'), findsOneWidget);
    expect(find.text('Public page'), findsOneWidget);
    // Isang View button lang sa table; nasa loob ng modal ang Approve / Reject.
    expect(find.text('View'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets('approve requires identity verification checkbox',
      (tester) async {
    final ds = await _pump(tester);

    // Buksan ang View modal, tapos doon ang Approve.
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve & delete'));
    await tester.pumpAndSettle();

    final dialogApprove = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Approve & delete'),
    );
    expect(dialogApprove, findsOneWidget);
    expect(ds.processed, isEmpty);

    final approveButton = tester.widget<FilledButton>(dialogApprove).onPressed;
    expect(approveButton, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tester.widget<FilledButton>(dialogApprove).onPressed, isNotNull);

    // May search field na sa toolbar, kaya i-scope sa dialog ang TextField.
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Called the registered number',
    );
    await tester.tap(dialogApprove);
    await tester.pumpAndSettle();

    expect(ds.processed, hasLength(1));
    expect(ds.processed.single['request_id'], 'req-1');
    expect(ds.processed.single['action'], 'approve');
    expect(ds.processed.single['notes'], 'Called the registered number');

    // Hinayaan ang success toast na mag-expire bago magtapos ang test.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('reject requires a short reason', (tester) async {
    final ds = await _pump(tester);

    // Buksan ang View modal, tapos doon ang Reject.
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    final rejectRequest = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Reject request'),
    );
    expect(rejectRequest, findsOneWidget);

    await tester.tap(rejectRequest);
    await tester.pump();
    expect(
      find.text('Enter a short reason (3+ characters).'),
      findsOneWidget,
    );
    expect(ds.processed, isEmpty);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Could not verify the account owner',
    );
    await tester.tap(rejectRequest);
    await tester.pumpAndSettle();

    expect(ds.processed, hasLength(1));
    expect(ds.processed.single['action'], 'reject');
    expect(
      ds.processed.single['notes'],
      'Could not verify the account owner',
    );

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('status filter requests the right API status', (tester) async {
    final ds = await _pump(tester, rows: [
      _request(),
      _request(
        id: 'req-2',
        reference: 'DEL-DONE1',
        fullName: 'Ben Santos',
        status: 'completed',
      ),
    ]);

    expect(ds.requestedStatuses.first, 'pending');
    expect(find.text('DEL-DONE1'), findsNothing);

    // Status filter ay dropdown na, hindi na chips.
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed').last);
    await tester.pumpAndSettle();

    expect(ds.requestedStatuses.last, 'completed');
    expect(find.text('DEL-DONE1'), findsOneWidget);
    expect(find.text('Approve & delete'), findsNothing);
  });

  testWidgets('search filters the queue by name, reference, or contact',
      (tester) async {
    await _pump(tester, rows: [
      _request(),
      _request(id: 'req-2', reference: 'DEL-DONE1', fullName: 'Ben Santos'),
    ]);

    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(find.text('Ben Santos'), findsOneWidget);
    // Isa sa dalawang row ang tumutugma sa binabasa ng results chip.
    expect(find.text('2 results'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ben');
    await tester.pumpAndSettle();

    expect(find.text('Ana Cruz'), findsNothing);
    expect(find.text('Ben Santos'), findsOneWidget);
    expect(find.text('1 result'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'del-abc123');
    await tester.pumpAndSettle();

    expect(find.text('Ana Cruz'), findsOneWidget);
    expect(find.text('Ben Santos'), findsNothing);

    await tester.enterText(find.byType(TextField), 'wala-sa-listahan');
    await tester.pumpAndSettle();

    expect(find.text('No matching requests'), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
  });

  testWidgets('View action opens the details modal', (tester) async {
    await _pump(tester, rows: [_request(status: 'rejected')]);

    // Default filter ay pending — lumipat sa Rejected para lumabas ang row.
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rejected').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    for (final text in const [
      'Ana Cruz',
      'DEL-ABC123',
      '09171234567 (mobile)',
      'Lendee',
      'Public page',
      'I no longer use the app.',
      'Verified by phone call',
    ]) {
      expect(
        find.descendant(of: dialog, matching: find.text(text)),
        findsOneWidget,
        reason: 'hindi nakita sa modal: $text',
      );
    }

    // X na sa itaas ang pang-close, wala nang "Close" button sa ibaba.
    expect(find.descendant(of: dialog, matching: find.text('Close')),
        findsNothing);
    expect(
      find.descendant(
        of: dialog,
        matching: find.byIcon(Icons.close_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('list error shows retry state', (tester) async {
    final ds = _FakeAccountDeletionDataSource([_request()])..failList = true;

    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hmAccountDeletionProvider.overrideWith(
            (ref) => HmAccountDeletionNotifier(ds),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const Scaffold(body: HmAccountDeletionBody()),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Could not load requests'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    ds.failList = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('DEL-ABC123'), findsOneWidget);
  });

  test('route at Notification Center tab ang account deletion', () {
    final route =
        File('lib/core/constants/route_constants.dart').readAsStringSync();
    final router = File('lib/core/router/app_router.dart').readAsStringSync();
    final sidebar =
        File('lib/presentation/shared/widgets/layout/web_scaffold.dart')
            .readAsStringSync();
    final notificationCenter = File(
      'lib/presentation/features/head_manager/notifications/screens/'
      'hm_notification_center_screen.dart',
    ).readAsStringSync();

    expect(
      route,
      contains("hmAccountDeletion = '/hm/account-deletion'"),
    );
    expect(router, contains('RouteConstants.hmAccountDeletion'));
    // Parehong Notification Center ang bumubukas sa dalawang URI; ang URL ang
    // nagsasabi kung aling tab. Wala nang hiwalay na screen class.
    expect(router, contains('HmNotificationCenterScreen'));
    expect(router, isNot(contains('HmAccountDeletionScreen')));
    // Wala na sa side nav — nasa Notification Center tab na.
    expect(sidebar, isNot(contains("'Account Deletion'")));
    expect(sidebar, isNot(contains('RouteConstants.hmAccountDeletion')));
    expect(notificationCenter, contains("Tab(text: 'Account Deletion')"));
    expect(notificationCenter, contains('const HmAccountDeletionBody()'));
    expect(notificationCenter, isNot(contains("Tab(text: 'SMS Logs'")));
    // Sariling URI ng tab — ang tap ay naggo-go_router, hindi lang local tab
    // index, at ang header ay sumasabay sa aktibong tab.
    expect(notificationCenter, contains('RouteConstants.hmAccountDeletion'));
    expect(notificationCenter, contains('RouteConstants.hmNotifications'));
    expect(notificationCenter, contains('NeverScrollableScrollPhysics'));
    // Header title ng tab — hindi laging "Notification Center".
    expect(
      notificationCenter,
      contains("isDeletionTab ? 'Account Deletion Requests'"),
    );
  });

  test('listRequests uses POST — 405 ang GET sa edge function', () {
    final source = File(
      'lib/data/datasources/remote/account_deletion_remote_datasource.dart',
    ).readAsStringSync();
    final listStart = source.indexOf('listRequests');
    final listEnd = source.indexOf('processRequest', listStart);
    expect(listStart, greaterThanOrEqualTo(0));
    expect(listEnd, greaterThan(listStart));
    final listBody = source.substring(listStart, listEnd);

    expect(listBody, contains('_client.post'));
    expect(listBody, isNot(contains('_client.get')));
  });
}
