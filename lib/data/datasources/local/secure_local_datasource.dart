// lib/data/datasources/local/secure_local_datasource.dart
import '../../../core/security/secure_storage.dart';

class SecureLocalDataSource {
  Future<String?> getAccessToken() => SecureStorage.getAccessToken();
  Future<String?> getRefreshToken() => SecureStorage.getRefreshToken();
  Future<String?> getUserId() => SecureStorage.getUserId();
  Future<String?> getUserRole() => SecureStorage.getUserRole();

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) =>
      SecureStorage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

  Future<void> saveUserInfo({
    required String userId,
    required String role,
  }) =>
      SecureStorage.saveUserInfo(userId: userId, role: role);

  Future<void> clearAll() => SecureStorage.clearAll();
  Future<bool> hasValidSession() => SecureStorage.hasValidSession();
}
