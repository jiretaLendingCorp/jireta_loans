// lib/core/network/interceptors/auth_interceptor.dart
import 'package:dio/dio.dart';

import '../../config/env_config.dart';
import '../../constants/app_constants.dart';
import '../../security/secure_storage.dart';

class AuthInterceptor extends Interceptor {
  final Dio _dio;
  bool _isRefreshing = false;

  AuthInterceptor(this._dio);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await SecureStorage.getAccessToken();
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
          return handler.resolve(retryResponse);
        }
      } catch (_) {
        await SecureStorage.clearAll();
      }
      _isRefreshing = false;
    }
    handler.next(err);
  }
}
