// lib/core/network/interceptors/auth_interceptor.dart
import 'package:dio/dio.dart';

import '../../config/env_config.dart';
import '../../constants/app_constants.dart';
import '../../security/secure_storage.dart';

// Endpoints that don't own a session — a 401 from them means bad credentials,
// NOT an expired token. Never attempt a refresh for these paths.
const _noRefreshPaths = {
  'auth-login?fn=login',
  'auth-otp?fn=send-otp',
  'auth-otp?fn=verify-otp',
  'auth-password?fn=forgot-password',
  'auth-password?fn=reset-password',
  'auth-logout?fn=logout',
  'auth-google?fn=exchange',
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
          // FIX: A retried 4xx/5xx must be surfaced as an error, not swallowed.
          // Previously `handler.resolve(retryResponse)` was used unconditionally,
          // so a refresh-retried request that still failed (e.g. force-change-
          // password with a wrong current password) was treated as SUCCESS.
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
        // FIX: 401 without a usable refresh token — the stored access token
        // can never be repaired (e.g. a magic-link `hashed_token` got saved as
        // the JWT). Drop the broken session so the next launch forces a clean
        // login instead of looping on "Invalid JWT format".
        await SecureStorage.clearAll();
      } catch (_) {
        await SecureStorage.clearAll();
      }
      _isRefreshing = false;
    }
    handler.next(err);
  }
}
