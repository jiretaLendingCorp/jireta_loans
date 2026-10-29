// test/features/head_manager/ci/hm_ci_details_workflow_test.dart
//
// WORKFLOW PROGRESS NG CI DETAILS (HM)
//
// Dating naka-full-width outlined button ang "Back to CI List" sa top bar —
// ngayon arrow icon na lang ito (may tooltip para hindi mawala ang label sa
// accessibility).
//
// Ang stepper naman ay pantay na hinahati sa lima ang lapad ng card (dating
// naka-hardcode na 96/110px bawat step), kaya pantay ang agwat ng mga dot at
// label, at may tuloy-tuloy na track sa likod ng mga dot. Kapag rejected,
// "Rejected" ang huling stage at pula ito — hindi na "Approved".
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:jireta_loans/core/di/injection.dart';
import 'package:jireta_loans/data/datasources/remote/auth_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/ci_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/data/models/user_model.dart';
import 'package:jireta_loans/presentation/features/head_manager/ci/screens/hm_ci_details_screen.dart';
import 'package:jireta_loans/presentation/features/head_manager/profile/providers/hm_profile_provider.dart';
import 'package:jireta_loans/presentation/shared/providers/auth_state_provider.dart';
import 'package:jireta_loans/presentation/shared/providers/ci_detail_provider.dart';

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

UserModel _headManager() => UserModel(
      id: 'hm-1',
      role: 'head_manager',
      firstName: 'Mylene',
      lastName: 'Cayabyab',
      accountStatus: 'active',
      forcePasswordChange: false,
      createdAt: DateTime.now(),
    );

class _FakeAuthNotifier extends AuthStateNotifier {
  _FakeAuthNotifier() {
    state = AuthState(isAuthenticated: true, user: _headManager());
  }
}

class _FakeProfileNotifier extends HmProfileNotifier {
  _FakeProfileNotifier(super.userDs, super.authDs);

  @override
  Future<void> loadProfile({bool silent = false}) async {
    state = HmProfileState(user: _headManager());
  }
}

Map<String, dynamic> _ci(String status) => {
      'id': 'ci1abcdef1234567890',
      'loan_id': 'loan-1',
      'status': status,
      'created_at': '2026-10-21T00:30:00Z',
      'deadline': '2026-10-24T00:00:00Z',
      'response_at': status == 'assigned' ? null : '2026-10-21T01:00:00Z',
      'completed_at':
          ['completed', 'approved', 'rejected'].contains(status)
              ? '2026-10-22T02:00:00Z'
              : null,
      'investigation_notes': 'Verify borrower address and employment.',
      'report_summary': 'Address confirmed.',
      'ci_documents': <dynamic>[],
      'loans': {
        'loan_number': 'LN-2026-916379',
        'principal_amount': 3500,
        'lender_address': {
          'street': 'Pedro',
          'barangay': 'Esperanza',
          'city': 'Dilasag',
          'province': 'Aurora',
        },
        'lender_profile': {
          'users': {'first_name': 'Mike', 'last_name': 'Nindo'},
        },
      },
      'rider': {
        'users': {'first_name': 'Jay', 'last_name': 'Shin'},
      },
      'assigned_by_user': {'first_name': 'Myline', 'last_name': 'Cayabyab'},
    };

class _StubCiDetailNotifier extends CiDetailNotifier {
  _StubCiDetailNotifier(Map<String, dynamic> ci)
      : super(CiRemoteDataSource(DioClientFake()), ci['id'] as String) {
    state = CiDetailState(ci: ci);
  }

  @override
  Future<void> fetch({bool silent = false}) async {}
}

void main() {
  setUpAll(loadTestEnv);

  setUp(() async {
    sl.allowReassignment = true;
    await setupDependencies();
    if (!GetIt.instance.isRegistered<NotificationRemoteDataSource>()) {
      GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
          () => NotificationRemoteDataSource(DioClientFake()));
    }
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pumpDetails(
    WidgetTester tester,
    Map<String, dynamic> ci, {
    Size size = const Size(1366, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/hm/ci/ci1',
      routes: [
        GoRoute(
          path: '/hm/ci/ci1',
          builder: (_, __) => const HmCiDetailsScreen(ciId: 'ci1'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => _FakeAuthNotifier()),
        hmProfileProvider.overrideWith(
          (ref) => _FakeProfileNotifier(
            sl<UserRemoteDataSource>(),
            sl<AuthRemoteDataSource>(),
          ),
        ),
        ciDetailProvider('ci1').overrideWith((ref) => _StubCiDetailNotifier(ci)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('back action: arrow icon lang, wala nang text na button',
      (tester) async {
    await pumpDetails(tester, _ci('approved'));

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Back to CI List'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.text('Back to CI List'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('stepper: pantay ang agwat ng limang stage',
      (tester) async {
    await pumpDetails(tester, _ci('approved'));

    expect(tester.takeException(), isNull);

    double centerX(String label) => tester.getCenter(find.text(label)).dx;

    final xs = [
      centerX('Assigned'),
      centerX('Accepted'),
      centerX('In Progress'),
      centerX('Submitted'),
      centerX('Approved'),
    ];

    final gaps = [
      xs[1] - xs[0],
      xs[2] - xs[1],
      xs[3] - xs[2],
      xs[4] - xs[3],
    ];
    for (final gap in gaps) {
      expect((gap - gaps.first).abs(), lessThan(1.0),
          reason: 'Dapat pantay ang agwat ng mga stage — $gaps');
    }
    // Nakasentro ang gitnang stage sa pagitan ng una at huli.
    expect((xs[2] - (xs[0] + xs[4]) / 2).abs(), lessThan(1.0));
  });

  testWidgets('rejected: "Rejected" ang huling stage, hindi "Approved"',
      (tester) async {
    await pumpDetails(tester, _ci('rejected'));

    expect(tester.takeException(), isNull);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Approved'), findsNothing);
  });

  testWidgets('mobile: vertical pa rin ang stepper at walang overflow',
      (tester) async {
    await pumpDetails(tester, _ci('in_progress'), size: const Size(390, 844));

    expect(tester.takeException(), isNull);
    expect(find.text('In Progress'), findsOneWidget);
  });
}
