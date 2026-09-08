// lib/core/security/session_ping.dart
import 'package:dio/dio.dart';

import '../config/env_config.dart';
import '../constants/app_constants.dart';
import 'secure_storage.dart';

enum SessionPingResult { ok, revoked, offline }

/// Lightweight session heartbeat used by [AuthStateNotifier] while the user
/// is authenticated.
///
/// Pings `auth-session?fn=ping` with the user's access token + stable
/// session id. The server's requireAuth → validate_active_session bumps
/// `last_seen_at`, so an open app keeps its active_sessions row "recently
/// seen" and continues to block other logins (first-login-wins). A
/// force-closed app stops pinging and its row expires after ~5 minutes, so
/// the account can never be locked by a dead session.
///
/// If the server answers SESSION_REVOKED (this device was superseded by a
/// fresh login on another device), the caller hard-logs-out.
class SessionPing {
  SessionPing._();

  static Future<SessionPingResult> ping() async {
    String? token;
    try {
      token = await SecureStorage.getAccessToken();
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) return SessionPingResult.offline;

    String? sessionId;
    try {
      sessionId = await SecureStorage.getSessionId();
    } catch (_) {
      sessionId = null;
    }

    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: '${EnvConfig.edgeFunctionsUrl}/',
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'apikey': EnvConfig.supabaseAnonKey,
            'Authorization': 'Bearer $token',
            if (sessionId != null && sessionId.isNotEmpty)
              AppConstants.sessionIdHeaderName: sessionId,
          },
        ),
      );
      final response = await dio.post(AppConstants.authPingPath);
      if (response.statusCode == 200) return SessionPingResult.ok;
      return SessionPingResult.offline;
    } on DioException catch (e) {
      // 401 SESSION_REVOKED → this device is no longer the active one.
      if (e.response?.statusCode == 401) return SessionPingResult.revoked;
      // Any other failure (offline, timeout, 5xx) is transient — keep the
      // session; the next heartbeat retries.
      return SessionPingResult.offline;
    } catch (_) {
      return SessionPingResult.offline;
    }
  }
}
