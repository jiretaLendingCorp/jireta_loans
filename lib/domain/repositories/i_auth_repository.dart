// lib/domain/repositories/i_auth_repository.dart
abstract class IAuthRepository {
  Future<Map<String, dynamic>> login(
      {required String email, required String password});
  Future<void> sendOtp({required String phone});
  Future<Map<String, dynamic>> verifyOtp(
      {required String phone, required String otp});
  Future<void> forceChangePassword(
      {required String currentPassword, required String newPassword});

  /// Returns the opaque reset-flow token the caller must keep for verify/reset
  /// (it replaces the email in the URL — see `reset_token.ts` in the backend).
  Future<String?> forgotPassword({required String email});
  Future<void> verifyResetOtp({
    required String otp,
    String? email,
    String? resetToken,
  });
  Future<void> resetPassword({
    required String otp,
    required String newPassword,
    String? email,
    String? resetToken,
    String? currentPassword,
  });
  // Legacy token-based reset kept for backwards compat (not used by new OTP flow)
  Future<void> resetPasswordWithToken(
      {required String token, required String newPassword});
  Future<void> logout();
  Future<Map<String, dynamic>> refreshSession({required String refreshToken});

  /// Verification ng email na inilagay sa "Fill In Information" — isang LINK
  /// ang ipinapadala sa email (hindi OTP code) at iyon ang nagpapatunay.
  Future<void> sendEmailVerification({required String email});
  Future<bool> isEmailVerified();

  /// Kinukumpirma ang token mula sa link ng email (walang kailangang session).
  Future<void> confirmEmailVerification({required String token});
}
