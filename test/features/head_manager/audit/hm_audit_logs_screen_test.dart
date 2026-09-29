import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jireta_loans/core/di/injection.dart';
import 'package:jireta_loans/data/datasources/remote/audit_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/head_manager/audit/audit_action_catalog.dart';
import 'package:jireta_loans/presentation/features/head_manager/audit/screens/hm_audit_logs_screen.dart';

import '../../../helpers/audit_test_helpers.dart';

class RecordingAuditDataSource extends AuditRemoteDataSource {
  RecordingAuditDataSource()
      : super(FakeDioClient((_) async => throw UnimplementedError()));

  final List<Map<String, dynamic>> calls = [];
  List<Map<String, dynamic>> logs = [];
  int totalPages = 1;
  Object? error;

  @override
  Future<Map<String, dynamic>> getAuditLogs({
    String? action,
    String? performedBy,
    String? tableName,
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    calls.add({
      'page': page,
      'action': action,
      'performed_by_name': performedBy,
      'limit': limit,
    });
    if (error != null) throw error!;
    return {
      'data': logs,
      'meta': {
        'page': page,
        'total_pages': totalPages,
        'total': logs.length * totalPages,
      },
    };
  }
}

Future<void> pumpAuditScreen(
  WidgetTester tester,
  RecordingAuditDataSource ds) async {
  sl.allowReassignment = true;
  sl.registerLazySingleton<AuditRemoteDataSource>(() => ds);

  final router = GoRouter(
    initialLocation: '/hm/audit',
    routes: [
      GoRoute(
        path: '/hm/audit',
        builder: (_, __) => const HmAuditLogsScreen(),
      ),
      GoRoute(
        path: '/hm/dashboard',
        builder: (_, __) => const Scaffold(body: SizedBox()),
      ),
    ],
  );

  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      theme: ThemeData(useMaterial3: true),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await loadTestEnv();
  });

  setUp(() async {
    sl.allowReassignment = true;
    await setupDependencies();
  });

  tearDown(() {
    sl.reset();
  });

  testWidgets('renders audit rows from the backend', (tester) async {
    final ds = RecordingAuditDataSource()
      ..logs = [
        auditLogRow(
            id: '1', action: 'loan_applied', tableName: 'loans',
            performedByUser: {'first_name': 'Jane', 'last_name': 'Doe'}),
        auditLogRow(
            id: '2', action: 'report_export', tableName: 'reports'),
      ];

    await pumpAuditScreen(tester, ds);

    expect(find.text('Audit Logs'), findsOneWidget);
    expect(find.text('Loan Applied'), findsOneWidget);
    expect(find.text('Report Export'), findsOneWidget);
    expect(find.text('Jane Doe'), findsOneWidget);
    expect(ds.calls.first['page'], 1);
  });

  testWidgets('action filter dropdown lists the real backend actions',
      (tester) async {
    final ds = RecordingAuditDataSource()..logs = [auditLogRow()];
    await pumpAuditScreen(tester, ds);

    final dropdown =
        tester.widget<DropdownButton<String?>>(find.byType(DropdownButton<String?>));
    expect(dropdown.items, hasLength(AuditActionCatalog.actions.length + 1));
    final values = dropdown.items!
        .map((i) => i.value)
        .whereType<String>()
        .toSet();
    expect(values, AuditActionCatalog.actions.toSet());
  });

  testWidgets('selecting an action triggers a filtered fetch', (tester) async {
    final ds = RecordingAuditDataSource()..logs = [auditLogRow()];
    await pumpAuditScreen(tester, ds);
    final callsBefore = ds.calls.length;

    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Loan Reject').last);
    await tester.pumpAndSettle();

    expect(ds.calls.length, callsBefore + 1);
    expect(ds.calls.last['action'], 'loan_reject');
  });

  testWidgets('search box sends performed_by_name after debounce',
      (tester) async {
    final ds = RecordingAuditDataSource()..logs = [auditLogRow()];
    await pumpAuditScreen(tester, ds);

    await tester.enterText(find.byType(TextField), 'Jane Doe');
    await tester.pump(const Duration(milliseconds: 500));

    expect(ds.calls.last['performed_by_name'], 'Jane Doe');
  });

  testWidgets('clearing the search box clears the filter', (tester) async {
    final ds = RecordingAuditDataSource()..logs = [auditLogRow()];
    await pumpAuditScreen(tester, ds);

    await tester.enterText(find.byType(TextField), 'Jane');
    await tester.pump(const Duration(milliseconds: 500));
    expect(ds.calls.last['performed_by_name'], 'Jane');

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 500));
    expect(ds.calls.last['performed_by_name'], isNull);
  });

  testWidgets('pagination requests the next page', (tester) async {
    final ds = RecordingAuditDataSource()
      ..logs = List.generate(5, (i) => auditLogRow(id: '$i'))
      ..totalPages = 3;
    await pumpAuditScreen(tester, ds);

    expect(find.text('Page 1 of 3'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    await tester.pump();

    expect(ds.calls.last['page'], 2);
    expect(find.text('Page 2 of 3'), findsOneWidget);
  });

  testWidgets('expanding a row shows before/after values', (tester) async {
    final ds = RecordingAuditDataSource()
      ..logs = [
        auditLogRow(
          id: '1',
          action: 'loan_approve',
          oldValues: {'status': 'pending'},
          newValues: {'status': 'approved'},
        ),
      ];
    await pumpAuditScreen(tester, ds);

    expect(find.text('BEFORE'), findsNothing);
    await tester.tap(find.text('Loan Approve'));
    await tester.pump();

    expect(find.text('BEFORE'), findsOneWidget);
    expect(find.text('AFTER'), findsOneWidget);
    // Bawat row ay label + value na hiwalay na Text widget.
    expect(find.text('Status:'), findsNWidgets(2));
    expect(find.text('pending'), findsOneWidget);
    expect(find.text('approved'), findsOneWidget);
  });

  testWidgets('hindi ipinapakita ang panloob na DB column sa BEFORE',
      (tester) async {
    // Ang `old_values` ng "Update Profile" ay BUONG dating row (`select *`),
    // kaya dati ay lumalabas ang id / role_id / fcm_token / created_at /
    // updated_at / last_login_at na puro "—". Ang `new_values` naman ay
    // payload lang ng update (malinis). Dapat magkatugma ang keys ng dalawang
    // panig: tanging ang TALAGANG nagbago.
    final ds = RecordingAuditDataSource()
      ..logs = [
        auditLogRow(
          id: '1',
          action: 'update_profile',
          tableName: 'users',
          oldValues: {
            'id': '8756f4f3-ea8e-49ea-930f-08a252f779ed',
            'role_id': '07a4cd0f-c96e-4a77-bc30-4bcb8b95aed8',
            'fcm_token': null,
            'created_at': '2026-09-29T12:21:25.391385+00:00',
            'created_by': null,
            'updated_at': '2026-09-29T20:21:26.492693+00:00',
            'last_login_at': null,
            'first_name': null,
            'phone_number': '09568966622',
          },
          newValues: {
            'role': 'lender',
            'first_name': 'Mary Joy',
            'phone_number': '09568966622',
          },
        ),
      ];
    await pumpAuditScreen(tester, ds);
    await tester.tap(find.text('Update Profile'));
    await tester.pump();

    // Panloob na column: wala sa kahit anong panig.
    for (final hidden in const [
      'ID:',
      'Role Id:',
      'Fcm Token:',
      'Created At:',
      'Created By:',
      'Updated At:',
      'Last Login At:',
    ]) {
      expect(find.text(hidden), findsNothing, reason: hidden);
    }

    // Nagbago: `role` (wala sa dating row) at `first_name` (— → Mary Joy).
    // Magkatugma ang keys ng BEFORE at AFTER.
    expect(find.text('Role:'), findsNWidgets(2));
    expect(find.text('First Name:'), findsNWidgets(2));
    expect(find.text('lender'), findsOneWidget);
    expect(find.text('Mary Joy'), findsOneWidget);

    // Hindi nagbago ang numero → hindi kasama sa diff.
    expect(find.text('Phone Number:'), findsNothing);
  });

  testWidgets('shows empty state when there are no logs', (tester) async {
    final ds = RecordingAuditDataSource();
    await pumpAuditScreen(tester, ds);

    expect(find.text('No audit logs found'), findsOneWidget);
  });

  testWidgets('shows an error state with retry when fetch fails',
      (tester) async {
    final ds = RecordingAuditDataSource()
      ..error = Exception('boom')
      ..logs = [auditLogRow()];
    await pumpAuditScreen(tester, ds);

    expect(find.text('Failed to load audit logs. Please try again.'),
        findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    ds.error = null;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Loan Applied'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });
}
