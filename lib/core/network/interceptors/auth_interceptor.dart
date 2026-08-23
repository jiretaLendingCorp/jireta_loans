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

    // Extract server code to avoid blind refresh on irrecoverable 401s.
    // UNAUTHORIZED_ANON_TOKEN / USER_NOT_FOUND / MISSING_HEADER will never
    // succeed with a refresh – they indicate no session or DB desync.
    String? serverCode;
    final respData = err.response?.data;
    if (respData is Map) {
      final errObj = respData['error'];
      if (errObj is Map) serverCode = errObj['code']?.toString();
    }
    // Don't waste a refresh on anon/missing/user-not-found – they need re-login.
    if (serverCode == 'UNAUTHORIZED_ANON_TOKEN' ||
        serverCode == 'UNAUTHORIZED_USER_NOT_FOUND' ||
        serverCode == 'UNAUTHORIZED_MISSING_HEADER' ||
        serverCode == 'UNAUTHORIZED_EMPTY_TOKEN') {
      // No refresh token will fix a missing DB row or an anon token sent
      // because SecureStorage was empty. Surface 401 and let UI re-login.
      // Only auto-logout if we can confirm no valid session – avoids
      // logging out a user who is simply offline (where response is null).
      if (serverCode == 'UNAUTHORIZED_USER_NOT_FOUND') {
        await _dropDeadSession();
      }
      return handler.next(err);
    }

    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;
      try {
        // Re-read refresh token fresh – another refresher (AuthStateNotifier)
        // may have already rotated it (enable_refresh_token_rotation=true race).
        String? refreshToken;
        try {
          refreshToken = await SecureStorage.getRefreshToken();
        } catch (_) {
          refreshToken = null;
        }
        if (refreshToken != null && refreshToken.isNotEmpty) {
          final response = await _dio.post(
            AppConstants.authRefreshPath,
            data: {'refresh_token': refreshToken},
          );
          final newAccessToken = response.data['access_token'];
          final newRefreshToken = response.data['refresh_token'];
          if (newAccessToken is! String || newAccessToken.isEmpty) {
            await _dropDeadSession();
            _isRefreshing = false;
            return handler.next(err);
          }
          await SecureStorage.saveTokens(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken is String ? newRefreshToken : refreshToken,
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
            // Retry still 401 → refresh succeeded but new token still rejected
            // (e.g. DB row deleted). Drop session so UI doesn't loop.
            if (status == 401) await _dropDeadSession();
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
        // Handle rotation race: if 401, re-read token – maybe another
        // concurrent refresher already succeeded and stored a new token.
        if (refreshErr.response?.statusCode == 401) {
          try {
            final currentRefresh = await SecureStorage.getRefreshToken();
            // If storage now holds a DIFFERENT token than we tried, a
            // concurrent refresh succeeded – don't wipe it. The original
            // request will be retried on next user action via fresh token.
            // Only wipe if token is same or empty.
            if (currentRefresh == null || currentRefresh.isEmpty) {
              await _dropDeadSession();
            } else {
              // Try one more time with the new token (max 1 retry to avoid loop)
              try {
                final retryResp = await _dio.post(
                  AppConstants.authRefreshPath,
                  data: {'refresh_token': currentRefresh},
                );
                final na = retryResp.data['access_token'];
                final nr = retryResp.data['refresh_token'];
                if (na != null && na is String && na.isNotEmpty) {
                  await SecureStorage.saveTokens(
                    accessToken: na,
                    refreshToken: nr is String ? nr : currentRefresh,
                  );
                  _isRefreshing = false;
                  // Resolve by retrying original request with new token
                  err.requestOptions.headers['Authorization'] = 'Bearer $na';
                  final retry2 = await _dio.request(
                    err.requestOptions.path,
                    options: Options(
                      method: err.requestOptions.method,
                      headers: err.requestOptions.headers,
                    ),
                    data: err.requestOptions.data,
                    queryParameters: err.requestOptions.queryParameters,
                  );
                  if (retry2.statusCode != null && retry2.statusCode! < 400) {
                    return handler.resolve(retry2);
                  }
                }
              } catch (_) {
                await _dropDeadSession();
              }
            }
          } catch (_) {
            await _dropDeadSession();
          }
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
