// lib/core/network/interceptors/auth_interceptor.dart
import 'package:dio/dio.dart';

import '../../config/env_config.dart';
import '../../constants/app_constants.dart';
import '../../security/jwt_parser.dart';
import '../../security/session_events.dart';
import '../../security/session_refresher.dart';
import '../../security/secure_storage.dart';

// Endpoints that don't own a session — a 401 from them means bad credentials,
// NOT an expired token. Never attempt a refresh for these paths.
const _noRefreshPaths = {
  'auth-login?fn=login',
  'auth-otp?fn=send-otp',
  'auth-otp?fn=verify-otp',
  'auth-password?fn=forgot-password',
  'auth-password?fn=verify-otp',
  'auth-password?fn=reset-password',
  'auth-logout?fn=logout',
  'auth-google?fn=exchange',
  // Refreshing must never recurse: if the refresh call itself 401s, surface
  // the error instead of trying to refresh the refresher.
  AppConstants.authRefreshPath,
};

class AuthInterceptor extends Interceptor {
  final Dio _dio;

  AuthInterceptor(this._dio);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // FIX: If SecureStorage throws on web (e.g. WebCrypto/IndexedDB
    // unavailable before first interaction), a raw exception in onRequest aborts
    // the whole request → Dio wraps it as DioExceptionType.unknown → the UI
    // misleadingly reports "can't reach the server". Instead we swallow a storage
    // failure and fall back to the anon key so the request still goes out and the
    // real server response surfaces.
    String? token;
    try {
      token = await SecureStorage.getAccessToken();
    } catch (_) {
      token = null;
    }

    final path = options.path;
    final isRefreshPath = path == AppConstants.authRefreshPath;
    final ownsNoSession = _noRefreshPaths.contains(path);

    // ── Absolute 1-hour hard expiry: if session started >1h ago, hard logout ──
    // Do NOT attempt soft refresh — 1 hour is absolute, must re-login.
    // Grace already applied in isAbsoluteSessionExpired (30s leeway).
    bool isAbsoluteExpired = false;
    try {
      isAbsoluteExpired = await SecureStorage.isAbsoluteSessionExpired();
      // Only enforce absolute check if we have a startedAt timestamp.
      // Legacy sessions without timestamp fall back to JWT-only logic.
      final startedAt = await SecureStorage.getSessionStartedAt();
      if (startedAt == null) isAbsoluteExpired = false;
    } catch (_) {
      isAbsoluteExpired = false;
    }
    if (isAbsoluteExpired && !ownsNoSession && !isRefreshPath) {
      // Extra stale guard: if token is still fresh, this expiry is from an old
      // session that hasn't been overwritten yet — don't kill the new login.
      bool isStale = false;
      try {
        if (token != null && token.isNotEmpty && !JwtParser.isExpired(token)) {
          final remaining = await SecureStorage.getRemainingSessionTime();
          // If remaining is null (legacy) but JWT is fresh, treat as stale.
          // If remaining is still positive, also stale (new session just created).
          if (remaining == null || remaining.inSeconds > 10) isStale = true;
        }
      } catch (_) {}
      if (!isStale) {
        await _dropDeadSession();
        token = null;
      }
    } else if (token != null &&
        token.isNotEmpty &&
        !ownsNoSession &&
        (JwtParser.isExpired(token) || JwtParser.isExpiringSoon(token))) {
      // Soft JWT expiry within 1h window → try refresh without extending absolute deadline
      // Proactive: also refresh if expiring within 60s to avoid sending a token that
      // will expire during the request. If absolute is about to expire, the refresh
      // will be wasted but still handled as hard logout on next request.
      // Never block the request on a failed refresh — just fall back to anon if needed.
      try {
        final refreshResult = await SessionRefresher.refresh();
        if (refreshResult == SessionRefreshResult.success) {
          try {
            token = await SecureStorage.getAccessToken();
          } catch (_) {
            token = null;
          }
        } else if (refreshResult == SessionRefreshResult.authRejected) {
          await _dropDeadSession();
          token = null;
        }
        // offline → keep old token, let request try (server may still accept if not yet expired)
      } catch (_) {}
    }

    if (token != null && token.isNotEmpty && !ownsNoSession) {
      // Authenticated request: use the stored user JWT.
      options.headers['Authorization'] = 'Bearer $token';
    } else {
      // Unauthenticated request (e.g. login, OTP).
      // Supabase gateway still requires a valid Bearer token to let the
      // request reach the Edge Function. Fall back to the anon key so
      // the gateway passes the request through.
      options.headers['Authorization'] = 'Bearer ${EnvConfig.supabaseAnonKey}';
    }
    // The refresh call MUST carry a always-valid Bearer JWT. The Supabase
    // gateway verifies the bearer BEFORE invoking the function, so attaching
    // the possibly-expired user token here gets the refresh itself rejected
    // with a gateway 401 — an unrecoverable death spiral. The anon key is a
    // valid non-expiring JWT; auth-session validates the refresh_token itself.
    if (isRefreshPath) {
      options.headers['Authorization'] = 'Bearer ${EnvConfig.supabaseAnonKey}';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final path = err.requestOptions.path;

    // Auth endpoints that don't carry a session must NEVER trigger a refresh.
    if (_noRefreshPaths.contains(path)) {
      return handler.next(err);
    }

    // Extract server code to avoid blind refresh on irrecoverable 401s.
    // These indicate missing auth headers or a backend account-sync problem,
    // not an expired access token. Surface the real error instead of clearing
    // a still-refreshable session and showing a false "session expired".
    String? serverCode;
    final respData = err.response?.data;
    if (respData is Map) {
      final errObj = respData['error'];
      if (errObj is Map) serverCode = errObj['code']?.toString();
    }
    if (serverCode == 'UNAUTHORIZED_ANON_TOKEN' ||
        serverCode == 'UNAUTHORIZED_USER_NOT_FOUND' ||
        serverCode == 'UNAUTHORIZED_MISSING_HEADER' ||
        serverCode == 'UNAUTHORIZED_EMPTY_TOKEN') {
      return handler.next(err);
    }

    if (err.response?.statusCode == 401) {
      // ── Stale 401 guard for multiple logins ───────────────────────────
      // If the 401 came from an OLD token (first login) but we've already
      // logged in again (second login) and current stored token is different,
      // don't clear the new session. This fixes "second login expired immediately".
      try {
        final failedHeader = err.requestOptions.headers['Authorization']?.toString() ?? '';
        final failedToken = failedHeader.startsWith('Bearer ') ? failedHeader.substring(7) : failedHeader;
        final currentToken = await SecureStorage.getAccessToken();
        if (currentToken != null && currentToken.isNotEmpty && failedToken.isNotEmpty && currentToken != failedToken && !JwtParser.isExpired(currentToken)) {
          // Current session is fresh and valid, the 401 is stale from old session
          return handler.next(err);
        }
      } catch (_) {}

      // Hard 1h check before soft refresh: if absolute expired, never refresh
      bool absoluteExpired = false;
      try {
        final startedAt = await SecureStorage.getSessionStartedAt();
        if (startedAt != null) {
          absoluteExpired = await SecureStorage.isAbsoluteSessionExpired();
        }
      } catch (_) {}
      if (absoluteExpired) {
        // Double-check stale: if remaining >10s, it's a stale hard expiry from old session
        try {
          final remaining = await SecureStorage.getRemainingSessionTime();
          if (remaining != null && remaining.inSeconds > 10) {
            return handler.next(err);
          }
        } catch (_) {}
        await _dropDeadSession();
        return handler.next(err);
      }

      try {
        final result = await SessionRefresher.refresh();
        if (result == SessionRefreshResult.success) {
          final newAccessToken = await SecureStorage.getAccessToken();
          if (newAccessToken == null || newAccessToken.isEmpty) {
            await _dropDeadSession();
            return handler.next(err);
          }
          err.requestOptions.headers['Authorization'] =
              'Bearer $newAccessToken';
          try {
            final retryResponse = await _dio.request(
              err.requestOptions.path,
              options: Options(
                method: err.requestOptions.method,
                headers: err.requestOptions.headers,
              ),
              data: err.requestOptions.data,
              queryParameters: err.requestOptions.queryParameters,
            );
            return handler.resolve(retryResponse);
          } on DioException catch (retryErr) {
            if (retryErr.response?.statusCode == 401) {
              await _dropDeadSession();
            }
            return handler.next(retryErr);
          }
        }

        if (result == SessionRefreshResult.authRejected) {
          await _dropDeadSession();
        }
      } catch (_) {
        await _dropDeadSession();
      }
    }
    handler.next(err);
  }

  Future<void> _dropDeadSession() async {
    // Stale guard: don't clear if a new second login has already created a fresh 1h session.
    // This fixes "second login expired immediately" where an in-flight 401 from the
    // first session's timer arrives after the second login has stored fresh tokens.
    try {
      final remaining = await SecureStorage.getRemainingSessionTime();
      if (remaining != null && remaining.inSeconds > 10) {
        // New session still valid (>10s left) → this drop is from an old/stale 401, ignore
        return;
      }
      // Legacy case: no absolute timestamp but JWT still valid and not expiring soon → stale
      if (remaining == null) {
        final token = await SecureStorage.getAccessToken();
        if (token != null &&
            token.isNotEmpty &&
            !JwtParser.isExpired(token) &&
            !JwtParser.isExpiringSoon(token)) {
          return;
        }
      }
      // Also guard against deleting a just-saved token that hasn't had time to
      // persist startedAt yet: if token is fresh (not expired) and startedAt is
      // missing, it might be a web storage lag — don't nuke.
      if (remaining != null && remaining.inSeconds <= -30) {
        // Truly expired (30s grace already in isAbsoluteSessionExpired) → allow drop
      } else if (remaining != null && remaining.inSeconds <= 10 && remaining.inSeconds > -30) {
        // Within grace window ( -30 .. 10 ) — could be clock skew, check JWT.
        // If JWT is still valid for >60s, this is likely a false positive.
        final token = await SecureStorage.getAccessToken();
        final secs = JwtParser.secondsUntilExpiry(token);
        if (secs != null && secs > 60) return;
      }
    } catch (_) {}
    await SecureStorage.clearAll();
    SessionEvents.emitSessionExpired();
  }
}
