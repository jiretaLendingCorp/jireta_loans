// lib/domain/repositories/i_auth_repository.dart
abstract class IAuthRepository {
  Future<Map<String, dynamic>> login(
      {required String email, required String password});
  Future<void> sendOtp({required String phone});
  Future<Map<String, dynamic>> verifyOtp(
      {required String phone, required String otp});
  Future<void> forceChangePassword(
      {required String currentPassword, required String newPassword});
  Future<void> forgotPassword({required String email});
  Future<void> verifyResetOtp({required String email, required String otp});
  Future<void> resetPassword(
      {required String email, required String otp, required String newPassword});
  // Legacy token-based reset kept for backwards compat (not used by new OTP flow)
  Future<void> resetPasswordWithToken(
      {required String token, required String newPassword});
  Future<void> logout();
  Future<Map<String, dynamic>> refreshSession({required String refreshToken});
}
