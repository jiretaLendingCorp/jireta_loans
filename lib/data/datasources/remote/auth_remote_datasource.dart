// lib/data/datasources/remote/auth_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';

class AuthRemoteDataSource {
  final DioClient _client;
  AuthRemoteDataSource(this._client);

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? sessionId,
  }) async {
    final res = await _client.post(
      ApiEndpoints.authLogin,
      data: {
        'email': email,
        'password': password,
        if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> register({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String otp,
  }) async {
    final res = await _client.post(
      ApiEndpoints.authRegister,
      data: {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'password': password,
        'otp': otp,
      },
    );
    return res.data as Map<String, dynamic>;
  }

  Future<void> sendRegisterOtp({
    required String email,
    String? firstName,
    String? lastName,
  }) async {
    await _client.post(
      ApiEndpoints.authRegisterSendOtp,
      data: {
        'email': email,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
      },
    );
  }

  Future<void> verifyRegisterOtp({
    required String email,
    required String otp,
  }) async {
    await _client.post(
      ApiEndpoints.authRegisterVerifyOtp,
      data: {'email': email, 'otp': otp},
    );
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
    String? sessionId,
  }) async {
    final res = await _client.post(
      ApiEndpoints.authVerifyOtp,
      data: {
        'phone_number': phone,
        'otp': otp,
        if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
      },
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
    String? sessionId,
  }) async {
    final res = await _client.post(
      ApiEndpoints.authGoogle,
      data: {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
      },
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

  /// Returns the opaque reset-flow token (64 hex chars, hash-like).
  ///
  /// SECURITY: the reset screen puts THIS in the URL instead of the email, so
  /// the account identifier never lands in browser history, access logs or the
  /// Referer header. The server resolves the token back to the email itself.
  Future<String?> forgotPassword({required String email}) async {
    final res = await _client.post(
      ApiEndpoints.authForgotPassword,
      data: {'email': email},
    );
    final data = res.data;
    if (data is Map && data['reset_token'] is String) {
      final token = data['reset_token'] as String;
      return token.isEmpty ? null : token;
    }
    return null;
  }

  /// [resetToken] is preferred: the email is then never sent at all.
  Future<void> verifyResetOtp({
    required String otp,
    String? email,
    String? resetToken,
  }) async {
    await _client.post(
      ApiEndpoints.authVerifyResetOtp,
      data: {
        'otp': otp,
        if (resetToken != null && resetToken.isNotEmpty)
          'reset_token': resetToken
        else
          'email': email,
      },
    );
  }

  Future<void> resetPassword({
    required String otp,
    required String newPassword,
    String? email,
    String? resetToken,
  }) async {
    await _client.post(
      ApiEndpoints.authResetPassword,
      data: {
        'otp': otp,
        'new_password': newPassword,
        if (resetToken != null && resetToken.isNotEmpty)
          'reset_token': resetToken
        else
          'email': email,
      },
    );
  }

  // Legacy token-based reset kept for backwards compat (not used by new OTP flow)
  Future<void> resetPasswordWithToken({
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

  /// Ipinapadala ang email-verification LINK (hindi OTP) sa [email]. Ang server
  /// ang gumagawa ng one-time token at ang Resend ang nagpapadala ng mail; dito
  /// lang sa app ipinapaalam kung umubra. Nagre-throw ito ng [DioException] na
  /// may mensahe ng server para maisauli sa user kung bakit hindi natuloy
  /// (hal. hindi pa naka-configure ang email sending).
  Future<void> sendEmailVerification({required String email}) async {
    await _client.post(
      ApiEndpoints.authEmailVerifySend,
      data: {'email': email},
    );
  }

  /// Kinukumpirma ang token na galing sa link ng email (branded na
  /// `/verify-email?t=...` page sa web app). Hindi kailangan ng naka-login na
  /// session — ang token mismo ang nagpapatunay kaya ligtas itong tawagin
  /// kahit naka-log out (hal. binuksan ng lender ang link sa browser).
  /// Nagre-throw ng [DioException] na may mensahe ng server kapag bigo (hal.
  /// expired o nagamit na ang link).
  Future<void> confirmEmailVerification({required String token}) async {
    await _client.get(
      ApiEndpoints.authEmailVerifyConfirm,
      queryParams: {'t': token},
    );
  }

  /// Kung verified na ba ang email ng naka-login na account. Sa `false`
  /// (hindi pa, o hindi mabasa ang tugon) ay nananatili ang user sa Verify
  /// Your Email screen — hindi ito naghuhulog ng error para hindi makagambala
  /// ang pansamantalang network glitch.
  Future<bool> isEmailVerified() async {
    final res = await _client.get(ApiEndpoints.authEmailVerifyStatus);
    final raw = res.data;
    if (raw is! Map<String, dynamic>) return false;
    return raw['verified'] == true;
  }
}
