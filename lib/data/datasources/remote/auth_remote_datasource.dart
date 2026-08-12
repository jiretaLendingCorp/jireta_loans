// lib/data/datasources/remote/auth_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';

class AuthRemoteDataSource {
  final DioClient _client;
  AuthRemoteDataSource(this._client);

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await _client.post(
      ApiEndpoints.authLogin,
      data: {'email': email, 'password': password},
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendOtp({required String phone}) async {
    final res = await _client.post(
      ApiEndpoints.authSendOtp,
      data: {'phone_number': phone},
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    final res = await _client.post(
      ApiEndpoints.authVerifyOtp,
      data: {'phone_number': phone, 'otp': otp},
    );
    return res.data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    await _client.post(ApiEndpoints.authLogout, data: {});
  }

  Future<Map<String, dynamic>> refreshSession({
    required String refreshToken,
  }) async {
    final res = await _client.post(
      ApiEndpoints.authRefreshSession,
      data: {'refresh_token': refreshToken},
    );
    return res.data as Map<String, dynamic>;
  }

  /// Exchanges a Google OAuth session (obtained via Supabase Auth) for an app
  /// session mapped to a lender account. The Edge Function verifies the token,
  /// resolves/auto-creates the lender, and returns fresh tokens + user info.
  Future<Map<String, dynamic>> googleExchange({
    required String accessToken,
    String? refreshToken,
  }) async {
    final res = await _client.post(
      ApiEndpoints.authGoogle,
      data: {'access_token': accessToken, 'refresh_token': refreshToken},
    );
    return res.data as Map<String, dynamic>;
  }

  Future<void> forceChangePassword({
    required String newPassword,
    required String currentPassword,
  }) async {
    await _client.post(
      ApiEndpoints.authForceChangePassword,
      data: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }

  Future<void> changePassword({
    required String newPassword,
    required String currentPassword,
  }) async {
    await _client.post(
      ApiEndpoints.authChangePassword,
      data: {'current_password': currentPassword, 'new_password': newPassword},
    );
  }

  Future<void> forgotPassword({required String email}) async {
    await _client.post(ApiEndpoints.authForgotPassword, data: {'email': email});
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await _client.post(
      ApiEndpoints.authResetPassword,
      data: {'token': token, 'new_password': newPassword},
    );
  }

  Future<void> acceptTerms({
    required String deviceId,
    required String platform,
    required String appVersion,
  }) async {
    await _client.post(
      ApiEndpoints.authTermsAccept,
      data: {
        'device_id': deviceId,
        'platform': platform,
        'app_version': appVersion,
      },
    );
  }
}
