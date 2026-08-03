// lib/core/security/secure_storage.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';

class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    // Flutter Web (Chrome) requires webOptions so storage is encrypted in
    // IndexedDB under a project-specific key+dbName.  Without this the package
    // uses its default key ("FlutterSecureStorage"), which collides with other
    // Flutter apps on the same origin and falls back to unencrypted storage on
    // some browsers — causing all authenticated requests to use the anon key
    // instead of the real user JWT and producing cascade 401s.
    //
    // FIX: was `wOptions:` (WindowsOptions — desktop only) which caused the
    // Dart compile-time error:
    //   "A value of type 'WebOptions' can't be assigned to a parameter of
    //    type 'WindowsOptions' in a const constructor."
    // Correct parameter for Flutter Web is `webOptions` (note: no 'w' prefix).
    webOptions: WebOptions(
      // ← FIXED (was: wOptions)
      dbName: 'jireta_secure_storage',
      publicKey: 'jireta_loans_pub_key',
    ),
  );

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: AppConstants.accessTokenKey, value: accessToken),
      _storage.write(key: AppConstants.refreshTokenKey, value: refreshToken),
    ]);
  }

  static Future<String?> getAccessToken() async {
    return _storage.read(key: AppConstants.accessTokenKey);
  }

  static Future<String?> getRefreshToken() async {
    return _storage.read(key: AppConstants.refreshTokenKey);
  }

  static Future<void> saveUserInfo({
    required String userId,
    required String role,
  }) async {
    await Future.wait([
      _storage.write(key: AppConstants.userIdKey, value: userId),
      _storage.write(key: AppConstants.userRoleKey, value: role),
    ]);
  }

  static Future<String?> getUserId() async {
    return _storage.read(key: AppConstants.userIdKey);
  }

  static Future<String?> getUserRole() async {
    return _storage.read(key: AppConstants.userRoleKey);
  }

  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  static Future<bool> hasValidSession() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
}
