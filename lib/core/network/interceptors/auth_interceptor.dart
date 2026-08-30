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

    // ── Idle 10-minute expiry: if no activity for 10m, hard logout ────────
    // Do NOT attempt soft refresh — idle window has been exceeded, must re-login.
    // Grace already applied in isIdleExpired (10s leeway).
    bool isIdleExpired = false;
    try {
      isIdleExpired = await SecureStorage.isIdleExpired();
      final lastActivity = await SecureStorage.getLastActivity();
      final startedAt = await SecureStorage.getSessionStartedAt();
      if (lastActivity == null && startedAt == null) isIdleExpired = false;
    } catch (_) {
      isIdleExpired = false;
    }
    if (isIdleExpired && !ownsNoSession && !isRefreshPath) {
      bool isStale = false;
      try {
        if (token != null && token.isNotEmpty && !JwtParser.isExpired(token)) {
          final remaining = await SecureStorage.getRemainingIdleTime();
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
      // Soft JWT expiry within idle 10m window → try refresh without extending idle deadline
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
      } catch (_) {}
    }

    // Any authenticated request counts as user activity → bump idle timer.
    // Do it after idle/refresh checks but before attaching the header so
    // the next 10-minute window starts now.  Fire-and-forget, never block.
    if (token != null && token.isNotEmpty && !ownsNoSession && !isRefreshPath) {
      try {
        // Intentionally not awaited with long timeout; just queue a write.
        // ignore: unawaited_futures
        SecureStorage.bumpActivity();
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
    // ── Archived account or archived role → immediate hard logout ──────────
    // Requirement: "KAPAG NAKA ARCHIVED UNG ROLE OR USER DAPAT HINDI MAGAGAMIT
    // NI USER UNG ACCOUNT NIYA" — any authenticated request after archiving
    // must force logout so the user cannot continue using the app.
    // ROLE_ARCHIVED = role disabled, ACCOUNT_ARCHIVED = user disabled.
    // Both clear storage and emit sessionExpired so router redirects to login.
    if (err.response?.statusCode == 403 &&
        (serverCode == 'ACCOUNT_ARCHIVED' ||
            serverCode == 'ROLE_ARCHIVED' ||
            serverCode == 'ACCOUNT_INACTIVE')) {
      await _dropDeadSession();
      return handler.next(err);
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

      // Hard idle check before soft refresh: if idle expired, never refresh
      bool idleExpired = false;
      try {
        final startedAt = await SecureStorage.getSessionStartedAt();
        final lastAct = await SecureStorage.getLastActivity();
        if (startedAt != null || lastAct != null) {
          idleExpired = await SecureStorage.isIdleExpired();
        }
      } catch (_) {}
      if (idleExpired) {
        try {
          final remaining = await SecureStorage.getRemainingIdleTime();
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
    // Stale guard: don't clear if a new second login has already created a fresh idle session.
    try {
      final remaining = await SecureStorage.getRemainingIdleTime();
      if (remaining != null && remaining.inSeconds > 10) return;
      if (remaining == null) {
        final token = await SecureStorage.getAccessToken();
        if (token != null &&
            token.isNotEmpty &&
            !JwtParser.isExpired(token) &&
            !JwtParser.isExpiringSoon(token)) {
          return;
        }
      }
      if (remaining != null && remaining.inSeconds <= -10) {
        // Truly idle-expired → allow drop
      } else if (remaining != null && remaining.inSeconds <= 10 && remaining.inSeconds > -10) {
        final token = await SecureStorage.getAccessToken();
        final secs = JwtParser.secondsUntilExpiry(token);
        if (secs != null && secs > 60) return;
      }
    } catch (_) {}
    await SecureStorage.clearAll();
    SessionEvents.emitSessionExpired();
  }
}
