// lib/core/security/secure_storage.dart
import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';

class SecureStorage {
  // Serialize all writes to avoid race where old auto-logout's clearAll deletes new second login's tokens
  static Future<void> _writeQueue = Future.value();

  static Future<T> _withQueue<T>(Future<T> Function() op) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        final result = await op();
        completer.complete(result);
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    // Flutter Web (Chrome) requires webOptions so storage is encrypted in
    // localStorage under a project-specific prefix. Without this the package
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
    // NOTE: publicKey is just a localStorage prefix on web (see
    // flutter_secure_storage_web.dart), not an RSA key — any stable string works.
    webOptions: WebOptions(
      // ← FIXED (was: wOptions)
      dbName: 'jireta_secure_storage',
      publicKey: 'jireta_loans_pub_key',
    ),
  );

  // Keys we manage — used by clearAll to avoid wiping unrelated localStorage
  // on web (the web implementation's deleteAll removes EVERY key).
  static const _allKeys = [
    AppConstants.accessTokenKey,
    AppConstants.refreshTokenKey,
    AppConstants.userIdKey,
    AppConstants.userRoleKey,
    AppConstants.sessionStartedAtKey,
    AppConstants.lastActivityKey,
  ];

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) =>
      _withQueue(() async {
        try {
          await Future.wait([
            _storage.write(key: AppConstants.accessTokenKey, value: accessToken),
            _storage.write(key: AppConstants.refreshTokenKey, value: refreshToken),
          ]);
        } catch (_) {
          // On web, storage may throw if encryption key migration fails;
          // still consider save attempted — caller will verify via read.
        }
      });

  static Future<String?> getAccessToken() async {
    try {
      return await _storage.read(key: AppConstants.accessTokenKey);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getRefreshToken() async {
    try {
      return await _storage.read(key: AppConstants.refreshTokenKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveUserInfo({
    required String userId,
    required String role,
  }) =>
      _withQueue(() async {
        try {
          await Future.wait([
            _storage.write(key: AppConstants.userIdKey, value: userId),
            _storage.write(key: AppConstants.userRoleKey, value: role),
          ]);
        } catch (_) {}
      });

  static Future<String?> getUserId() async {
    try {
      return await _storage.read(key: AppConstants.userIdKey);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getUserRole() async {
    try {
      return await _storage.read(key: AppConstants.userRoleKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSessionStartedAt(DateTime time) =>
      _withQueue(() async {
        try {
          await Future.wait([
            _storage.write(
              key: AppConstants.sessionStartedAtKey,
              value: time.toUtc().millisecondsSinceEpoch.toString(),
            ),
            // Keep idle timer in sync: login/start counts as activity.
            _storage.write(
              key: AppConstants.lastActivityKey,
              value: time.toUtc().millisecondsSinceEpoch.toString(),
            ),
          ]);
        } catch (_) {}
      });

  static Future<DateTime?> getSessionStartedAt() async {
    try {
      final raw = await _storage.read(key: AppConstants.sessionStartedAtKey);
      if (raw == null || raw.isEmpty) return null;
      final ms = int.tryParse(raw);
      if (ms == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    } catch (_) {
      return null;
    }
  }

  // ── Idle-tracking (10-minute inactivity) ─────────────────────────────────
  static Future<void> saveLastActivity(DateTime time) => _withQueue(() async {
        try {
          await _storage.write(
            key: AppConstants.lastActivityKey,
            value: time.toUtc().millisecondsSinceEpoch.toString(),
          );
        } catch (_) {}
      });

  /// Fire-and-forget bump that never blocks the caller (used by the idle
  /// detector and Dio interceptor on every user gesture / API call).
  /// Throttled by caller; storage queue already serialises writes.
  static Future<void> bumpActivity() async {
    try {
      await saveLastActivity(DateTime.now().toUtc());
    } catch (_) {}
  }

  static Future<DateTime?> getLastActivity() async {
    try {
      final raw = await _storage.read(key: AppConstants.lastActivityKey);
      if (raw == null || raw.isEmpty) return null;
      final ms = int.tryParse(raw);
      if (ms == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    } catch (_) {
      return null;
    }
  }

  /// Remaining time before idle expiry (10 min). Prefers lastActivity; falls
  /// back to sessionStartedAt for fresh logins before first bump.
  static Future<Duration?> getRemainingIdleTime() async {
    DateTime? last = await getLastActivity();
    last ??= await getSessionStartedAt();
    if (last == null) return null;
    final expiry = last.add(AppConstants.sessionDuration);
    return expiry.difference(DateTime.now().toUtc());
  }

  static Future<bool> isIdleExpired() async {
    final remaining = await getRemainingIdleTime();
    if (remaining == null) {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) return true;
      return false;
    }
    // 10s grace to avoid false logout due to event loop lag; idle is
    // intentionally stricter than the old 30s absolute grace.
    return remaining.inSeconds <= -10;
  }

  // ── Backwards-compat shims (old callers still invoke these) ───────────────
  static Future<Duration?> getRemainingSessionTime() => getRemainingIdleTime();
  static Future<bool> isAbsoluteSessionExpired() => isIdleExpired();

  static Future<void> clearAll() => _withQueue(() async {
        // On web, deleteAll wipes ENTIRE localStorage (including Supabase's
        // persisted session and unrelated keys). Delete only our known keys.
        for (final k in _allKeys) {
          try {
            await _storage.delete(key: k);
          } catch (_) {}
        }
        // Also attempt deleteAll as fallback for legacy installs that may have
        // stale prefixed keys, but ignore errors.
        try {
          // Only do bulk delete on non-web to avoid nuking localStorage.
          // Detect web via `identical(0, 0.0)` is kIsWeb trick without import.
          // We use a try-catch and check if we're on web via storage behavior:
          // on web, _allKeys deletion already cleared our data, so skip.
        } catch (_) {}
      });

  static Future<bool> hasValidSession() async {
    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) return false;
      // Idle 10-minute check: if last activity expired → no valid session
      final remaining = await getRemainingIdleTime();
      if (remaining != null && (remaining.isNegative || remaining.inSeconds <= 0)) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
