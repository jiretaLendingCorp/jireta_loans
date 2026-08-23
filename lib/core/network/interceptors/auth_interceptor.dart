// lib/core/network/interceptors/auth_interceptor.dart
import 'package:dio/dio.dart';

import '../../config/env_config.dart';
import '../../constants/app_constants.dart';
import '../../security/session_events.dart';
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
  bool _isRefreshing = false;

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

    if (token != null && token.isNotEmpty) {
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
    if (options.path == AppConstants.authRefreshPath) {
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

    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshToken = await SecureStorage.getRefreshToken();
        if (refreshToken != null && refreshToken.isNotEmpty) {
          final response = await _dio.post(
            AppConstants.authRefreshPath,
            data: {'refresh_token': refreshToken},
          );
          final newAccessToken = response.data['access_token'];
          final newRefreshToken = response.data['refresh_token'];
          await SecureStorage.saveTokens(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken,
          );
          err.requestOptions.headers['Authorization'] =
              'Bearer $newAccessToken';
          final retryResponse = await _dio.request(
            err.requestOptions.path,
            options: Options(
              method: err.requestOptions.method,
              headers: err.requestOptions.headers,
            ),
            data: err.requestOptions.data,
            queryParameters: err.requestOptions.queryParameters,
          );
          _isRefreshing = false;
          final status = retryResponse.statusCode;
          if (status != null && status >= 400) {
            final data = retryResponse.data;
            String msg = 'Request failed. Please try again.';
            if (data is Map) {
              final errObj = data['error'];
              final nested = errObj is Map ? errObj['message'] : null;
              final top = data['message'];
              msg = (nested as String?) ??
                  (top as String?) ??
                  'Request failed. Please try again.';
            }
            return handler.reject(DioException(
              requestOptions: err.requestOptions,
              response: retryResponse,
              message: msg,
              type: DioExceptionType.badResponse,
            ));
          }
          return handler.resolve(retryResponse);
        }
        // FIX: No refresh token stored — the session can never be repaired.
        // Clear it and tell the UI to auto-logout instead of leaving the app
        // stuck in a half-authenticated state.
        await _dropDeadSession();
      } on DioException catch (refreshErr) {
        // FIX: A 401 from the refresh endpoint means the refresh token itself
        // is invalid/expired → session cannot be recovered → auto-logout.
        // A connection-level failure (offline) must NOT clear the session —
        // the user just lost internet, don't log them out for that.
        if (refreshErr.response?.statusCode == 401) {
          await _dropDeadSession();
        }
      } catch (_) {
        await _dropDeadSession();
      }
      _isRefreshing = false;
    }
    handler.next(err);
  }

  Future<void> _dropDeadSession() async {
    await SecureStorage.clearAll();
    SessionEvents.emitSessionExpired();
  }
}
