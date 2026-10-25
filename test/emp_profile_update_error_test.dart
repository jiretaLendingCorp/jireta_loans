// test/emp_profile_update_error_test.dart
//
// REGRESSION: dating `EmpProfileNotifier.updateProfile` ay `bool` lang at
// hinihigop ang exception — kaya lahat ng failure (email na gamit na, invalid
// na numero, timeout) ay nagiging generic na "Failed to save changes" na walang
// sinasabi kung ano ang mali. Ngayon, ang AKTWAL na mensahe ng server ang
// ibinabalik para maipakita sa user.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/errors/app_exception.dart';
import 'package:jireta_loans/data/datasources/remote/user_remote_datasource.dart';
import 'package:jireta_loans/presentation/features/employee/profile/providers/emp_profile_provider.dart';

import 'helpers/audit_test_helpers.dart';

/// Ang base constructor ay naglo-load ng profile (network) — i-skip iyon sa
/// test; ang sinusukat lang dito ay ang update + error mapping.
class _TestNotifier extends EmpProfileNotifier {
  _TestNotifier(super.ds);

  @override
  Future<void> loadProfile({bool silent = false}) async {}
}

UserRemoteDataSource _ds(
  Future<Response<dynamic>> Function(RequestOptions options) handler,
) =>
    UserRemoteDataSource(FakeDioClient(handler));

void main() {
  setUpAll(loadTestEnv);

  test('duplicate email: aktwal na mensahe ng server ang ibinabalik', () async {
    final notifier = _TestNotifier(_ds((_) async {
      throw const AppException('Email already registered', code: 'DUPLICATE');
    }));

    final error = await notifier.updateProfile({'email': 'taken@example.com'});

    expect(error, 'Email already registered');
    notifier.dispose();
  });

  test('tagumpay: null ang ibinabalik', () async {
    final notifier = _TestNotifier(_ds(
      (options) async => Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: {'ok': true},
      ),
    ));

    expect(await notifier.updateProfile({'first_name': 'Michael'}), isNull);
    notifier.dispose();
  });

  test('blangkong mensahe: may makabuluhang fallback', () async {
    final notifier = _TestNotifier(_ds((_) async {
      throw const AppException('   ');
    }));

    expect(
      await notifier.updateProfile({'first_name': 'Michael'}),
      'Could not save your changes. Please try again.',
    );
    notifier.dispose();
  });
}
