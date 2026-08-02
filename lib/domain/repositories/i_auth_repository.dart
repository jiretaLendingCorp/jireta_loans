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
  Future<void> resetPassword(
      {required String token, required String newPassword});
  Future<void> logout();
  Future<Map<String, dynamic>> refreshSession({required String refreshToken});
}
