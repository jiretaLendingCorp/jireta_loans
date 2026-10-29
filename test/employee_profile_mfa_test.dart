// test/employee_profile_mfa_test.dart
//
// EMPLOYEE PROFILE > SECURITY > TWO-FACTOR AUTHENTICATION
//
// Dapat available din sa employee ang TOTP enrollment (QR + 6-digit code),
// kapareho ng rider/lender profile. Ito ang UI na nagpapa-enroll; ang login
// gate ang humihingi ng code pagkatapos ng email/password sign-in.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:jireta_loans/data/datasources/remote/notification_remote_datasource.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/employee/profile/screens/emp_profile_screen.dart';
import 'package:jireta_loans/presentation/shared/widgets/security/mfa_settings_card.dart';

import 'helpers/audit_test_helpers.dart';

Map<String, dynamic> _profileResponse() => {
      'user': {
        'id': '33333333-3333-3333-3333-333333333333',
        'role': 'employee',
        'first_name': 'Ana',
        'middle_name': null,
        'last_name': 'Cruz',
        'suffix': null,
        'email': 'ana@example.com',
        'phone_number': '09171234567',
        'account_status': 'active',
        'force_password_change': false,
        'profile_photo_url': null,
        'created_at': '2026-08-01T10:00:00.000Z',
        'last_login_at': '2026-09-27T10:00:00.000Z',
        'gender': 'female',
        'civil_status': 'single',
        'date_of_birth': '1998-04-12T00:00:00.000Z',
        'street_address': '12 Mabini St',
        'barangay': 'Poblacion',
        'city': 'Makati',
        'province': 'Metro Manila',
        'zip_code': '1210',
        'employee_profiles': {
          'position': 'Loan Processor',
        },
      },
    };

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_PH');
    await loadTestEnv();
    GetIt.instance.registerLazySingleton<NotificationRemoteDataSource>(
      () => NotificationRemoteDataSource(
        FakeDioClient((o) async => Response<dynamic>(
              requestOptions: o,
              data: {
                'data': <dynamic>[],
                'meta': {'unread_count': 0},
              },
            )),
      ),
    );
    GetIt.instance.registerLazySingleton<UserRemoteDataSource>(
      () => UserRemoteDataSource(
        FakeDioClient((o) async => Response<dynamic>(
              requestOptions: o,
              data: _profileResponse(),
            )),
      ),
    );
  });

  tearDownAll(() => GetIt.instance.reset());

  Future<void> pumpProfile(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/employee/profile',
      routes: [
        GoRoute(
          path: '/employee/profile',
          builder: (_, __) => const EmpProfileScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('may 2FA card sa employee profile (desktop at mobile)',
      (tester) async {
    await pumpProfile(tester, 1280);
    expect(find.byType(MfaSettingsCard), findsOneWidget);
    expect(find.text('Two-Factor Authentication'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpProfile(tester, 390);
    expect(find.byType(MfaSettingsCard), findsOneWidget);
    expect(find.text('Two-Factor Authentication'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
