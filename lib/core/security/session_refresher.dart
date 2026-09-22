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
    // ── ABSOLUTE session lifetime (3 buwan) ────────────────────────────────
    // Ang 10-minutong idle window ay PAG-LOCK lang (MPIN ang mag-u-unlock) at
    // HINDI dapat magpatalsik ng valid na refresh token. Dati, kapag lumampas
    // ang idle ay `authRejected` agad dito — kaya binubura ang session at
    // bumabalik ang rider/lender sa mobile-number (OTP) form makalipas lang
    // ng ilang minuto. Ngayon, ang ABSOLUTE na tagal (3 buwan) lang ang
    // nagtatapos ng session para sa muling pag-login ng numero.
    try {
      final startedAt = await SecureStorage.getSessionStartedAt();
      if (startedAt != null &&
          DateTime.now().toUtc().difference(startedAt) >=
              AppConstants.absoluteSessionDuration) {
        return SessionRefreshResult.authRejected;
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

      // Include the stable client session id so the refresh validates the
      // SAME session the client claimed at login (the JWT session_id claim
      // can rotate on refresh and would otherwise self-revoke the session).
      final sessionId = await SecureStorage.getSessionId();
      final response = await dio.post(
        AppConstants.authRefreshPath,
        data: {
          'refresh_token': refreshToken,
          if (sessionId != null && sessionId.isNotEmpty)
            'session_id': sessionId,
        },
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
        refreshToken: newRefreshToken is String && newRefreshToken.isNotEmpty
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
