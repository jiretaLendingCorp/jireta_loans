import 'package:dio/dio.dart';

import '../config/env_config.dart';
import '../constants/app_constants.dart';
import 'secure_storage.dart';

enum SessionRefreshResult { success, authRejected, offline }

class SessionRefresher {
  SessionRefresher._();

  static Future<SessionRefreshResult>? _inFlight;

  static Future<SessionRefreshResult> refresh() {
    final current = _inFlight;
    if (current != null) return current;

    final future = _refreshOnce();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
  }

  static Future<SessionRefreshResult> _refreshOnce() async {
    // Idle 10-minute hard expiry: never refresh if idle session already expired.
    // This enforces "after 10 min without activity must re-login".
    // Grace +10s to avoid clock-skew false positives.
    try {
      final isExpired = await SecureStorage.isIdleExpired();
      if (isExpired) {
        // Confirm remaining to avoid false logout on web storage lag.
        final remaining = await SecureStorage.getRemainingIdleTime();
        if (remaining != null) return SessionRefreshResult.authRejected;
      }
    } catch (_) {
      // If storage throws, proceed to normal refresh attempt
    }

    final refreshToken = await SecureStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return SessionRefreshResult.authRejected;
    }

    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: '${EnvConfig.edgeFunctionsUrl}/',
          connectTimeout: const Duration(milliseconds: 10000),
          receiveTimeout: const Duration(milliseconds: 10000),
          sendTimeout: const Duration(milliseconds: 10000),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'apikey': EnvConfig.supabaseAnonKey,
            'Authorization': 'Bearer ${EnvConfig.supabaseAnonKey}',
          },
        ),
      );

      final response = await dio.post(
        AppConstants.authRefreshPath,
        data: {'refresh_token': refreshToken},
      );
      final data = response.data;
      if (data is! Map) return SessionRefreshResult.authRejected;

      final newAccessToken = data['access_token'];
      final newRefreshToken = data['refresh_token'];
      if (newAccessToken is! String || newAccessToken.isEmpty) {
        return SessionRefreshResult.authRejected;
      }

      await SecureStorage.saveTokens(
        accessToken: newAccessToken,
        refreshToken:
            newRefreshToken is String && newRefreshToken.isNotEmpty
                ? newRefreshToken
                : refreshToken,
      );
      return SessionRefreshResult.success;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Only 401 is definitive "refresh token invalid/expired" → hard logout.
      // 429 (rate limit), 500, 400 etc are transient — keep session, retry later.
      if (status == 401) return SessionRefreshResult.authRejected;
      if (status != null) {
        // Got an HTTP response but not 401 → server reachable, but transient error.
        // Don't logout; treat as offline so the timer/overlay retries.
        return SessionRefreshResult.offline;
      }
      // No response → real network failure (timeout, DNS, offline)
      return SessionRefreshResult.offline;
    } catch (_) {
      // Unexpected error (e.g. JSON parse) — don't nuke session, retry.
      return SessionRefreshResult.offline;
    } finally {
      // Dio instance is short-lived; let GC collect. No close needed for this ephemeral Dio.
    }
  }
}
