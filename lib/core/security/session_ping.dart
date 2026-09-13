// lib/core/security/session_ping.dart
import 'package:dio/dio.dart';

import '../config/env_config.dart';
import '../constants/app_constants.dart';
import 'secure_storage.dart';
import 'session_refresher.dart';

enum SessionPingResult {
  ok,

  /// Tunay na revocation: ibang device ang naka-login na ngayon
  /// (`SESSION_REVOKED` — may sariwang active_sessions row na ibang id).
  revoked,

  /// Hindi na ma-repair ang session (expired/invalid na refresh token, o
  /// naabot ang 10-minutong idle limit) — kailangang mag-login muli, pero
  /// HINDI "may gumamit ng account sa ibang device".
  expired,

  /// Transient (offline, timeout, 5xx) — huwag galawin ang session.
  offline,
}

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
      final status = e.response?.statusCode;
      if (status == 401) {
        // HINDI lahat ng 401 ay revocation. Ang ping na ito ay hiwalay na Dio
        // (walang auth interceptor), kaya kapag na-expire na ang access token
        // — normal sa naka-background na app — 401 UNAUTHORIZED_INVALID_TOKEN
        // ang isinasagot ng server. Dati, tinatrato itong lahat na "signed in
        // on another device" at agad na nag-hahard-logout: iyon ang nagbibigay
        // ng maling "ended session" kahit walang ibang gumagamit.
        if (_serverCode(e.response?.data) == 'SESSION_REVOKED') {
          return SessionPingResult.revoked;
        }
        // Subukang i-repair ang token; kung pumasa, buhay pa ang session.
        final refreshed = await SessionRefresher.refresh();
        switch (refreshed) {
          case SessionRefreshResult.success:
            return SessionPingResult.ok;
          case SessionRefreshResult.authRejected:
            // Tunay na dead na ang refresh token (o naabot ang idle limit).
            return SessionPingResult.expired;
          case SessionRefreshResult.offline:
            return SessionPingResult.offline;
        }
      }
      // Any other failure (offline, timeout, 5xx) is transient — keep the
      // session; the next heartbeat retries.
      return SessionPingResult.offline;
    } catch (_) {
      return SessionPingResult.offline;
    }
  }

  /// Code ng server-side error (`{"error":{"code":"..."}}`) mula sa body.
  static String? _serverCode(dynamic data) {
    if (data is! Map) return null;
    final err = data['error'];
    if (err is Map) return err['code']?.toString();
    return null;
  }
}
