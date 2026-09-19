// lib/data/repositories/auth_repository_impl.dart
import '../../domain/repositories/i_auth_repository.dart';
import '../datasources/remote/auth_remote_datasource.dart';

class AuthRepositoryImpl implements IAuthRepository {
  final AuthRemoteDataSource _ds;
  AuthRepositoryImpl(this._ds);

  @override
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) =>
      _ds.login(email: email, password: password);

  @override
  Future<void> sendOtp({required String phone}) => _ds.sendOtp(phone: phone);

  @override
  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String otp,
  }) =>
      _ds.verifyOtp(phone: phone, otp: otp);

  @override
  Future<void> forceChangePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _ds.forceChangePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

  @override
  Future<String?> forgotPassword({required String email}) =>
      _ds.forgotPassword(email: email);

  @override
  Future<void> verifyResetOtp({
    required String otp,
    String? email,
    String? resetToken,
  }) =>
      _ds.verifyResetOtp(otp: otp, email: email, resetToken: resetToken);

  @override
  Future<void> resetPassword({
    required String otp,
    required String newPassword,
    String? email,
    String? resetToken,
    String? currentPassword,
  }) =>
      _ds.resetPassword(
        otp: otp,
        newPassword: newPassword,
        email: email,
        resetToken: resetToken,
        currentPassword: currentPassword,
      );

  @override
  Future<void> resetPasswordWithToken({
    required String token,
    required String newPassword,
  }) =>
      _ds.resetPasswordWithToken(token: token, newPassword: newPassword);

  @override
  Future<void> logout() => _ds.logout();

  @override
  Future<Map<String, dynamic>> refreshSession({required String refreshToken}) =>
      _ds.refreshSession(refreshToken: refreshToken);
}
