// lib/core/security/token_manager.dart
import 'secure_storage.dart';

class TokenManager {
  static Future<String?> getAccessToken() => SecureStorage.getAccessToken();
  static Future<String?> getRefreshToken() => SecureStorage.getRefreshToken();

  static Future<void> setTokens({
    required String accessToken,
    required String refreshToken,
  }) =>
      SecureStorage.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

  static Future<void> clearAll() => SecureStorage.clearAll();

  static Future<bool> hasValidSession() => SecureStorage.hasValidSession();

  static Future<void> saveUserInfo({
    required String userId,
    required String role,
  }) =>
      SecureStorage.saveUserInfo(userId: userId, role: role);

  static Future<String?> getUserId() => SecureStorage.getUserId();
  static Future<String?> getUserRole() => SecureStorage.getUserRole();
}
