// test/employee_mfa_flow_test.dart
//
// EMPLOYEE 2FA (TOTP) SA EMAIL/PASSWORD LOGIN
//
// Dating ang authenticator challenge ay para lang sa rider/lender OTP login at
// Google sign-in. Ngayon, kapag ang employee (o head manager) ay may verified
// TOTP factor sa Supabase Auth, kailangan muna ng 6-digit na code bago ang
// dashboard. Ang server response (`auth-login` → `mfa`) ang unang pinagkukunan
// ng katotohanan; ang Supabase Auth `getUser().factors` ang fallback.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:jireta_loans/core/security/secure_storage.dart';
import 'package:jireta_loans/data/datasources/remote/auth_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/auth/providers/auth_provider.dart';
import 'package:jireta_loans/presentation/shared/providers/auth_state_provider.dart';

String _jwt(Map<String, dynamic> payload) {
  final header =
      base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})));
  final body = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return '$header.$body.sig';
}

String _accessToken() => _jwt({
      'sub': '11111111-1111-1111-1111-111111111111',
      'role': 'authenticated',
      'aal': 'aal1',
      'iat': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      'exp': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch ~/
          1000,
    });

/// `auth-login` response para sa employee. [mfaEnabled] ang `mfa.enabled` na
/// iniuulat ng server.
class _FakeAuthRemoteDataSource implements AuthRemoteDataSource {
  _FakeAuthRemoteDataSource({required this.mfaEnabled});

  final bool mfaEnabled;

  @override
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? sessionId,
  }) async =>
      {
        'access_token': _accessToken(),
        'refresh_token': 'refresh-token',
        'user': {
          'id': '11111111-1111-1111-1111-111111111111',
          'role': 'employee',
          'email': 'employee@example.com',
          'first_name': 'Em',
          'last_name': 'Ployee',
          'force_password_change': false,
        },
        'mfa': {
          'enabled': mfaEnabled,
          'factors': mfaEnabled
              ? [
                  {'id': 'factor-1', 'friendly_name': 'Authenticator'},
                ]
              : <Map<String, dynamic>>[],
        },
      };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      publishableKey: _jwt({
        'iss': 'supabase',
        'ref': 'test',
        'role': 'anon',
        'iat': now,
        'exp': now + 3600,
      }),
    );
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('employee na may verified TOTP: mfaRequired at pending marker',
      () async {
    final authState = AuthStateNotifier();
    addTearDown(authState.dispose);
    final notifier =
        AuthNotifier(_FakeAuthRemoteDataSource(mfaEnabled: true), authState);
    addTearDown(notifier.dispose);

    final ok = await notifier.login(
      email: 'employee@example.com',
      password: 'secret',
    );

    expect(ok, isTrue);
    expect(authState.state.isAuthenticated, isTrue);
    expect(authState.state.role, 'employee');
    expect(authState.state.mfaRequired, isTrue);
    expect(notifier.loginMfa.enabled, isTrue);
    expect(notifier.loginMfa.factorId, 'factor-1');
    // Marker na binabasa ng `AuthStateNotifier.initialize` kapag nag-reload
    // habang hindi pa tapos ang challenge.
    expect(await SecureStorage.isMfaPending(), isTrue);
  });

  test('employee na walang TOTP: deretso sa dashboard, walang gate', () async {
    final authState = AuthStateNotifier();
    addTearDown(authState.dispose);
    final notifier =
        AuthNotifier(_FakeAuthRemoteDataSource(mfaEnabled: false), authState);
    addTearDown(notifier.dispose);

    await notifier.login(email: 'employee@example.com', password: 'secret');

    expect(authState.state.mfaRequired, isFalse);
    expect(await SecureStorage.isMfaPending(), isFalse);
  });
}
