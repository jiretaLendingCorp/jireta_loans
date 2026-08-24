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

    if (token != null &&
        token.isNotEmpty &&
        !ownsNoSession &&
        JwtParser.isExpired(token)) {
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
    await SecureStorage.clearAll();
    SessionEvents.emitSessionExpired();
  }
}
