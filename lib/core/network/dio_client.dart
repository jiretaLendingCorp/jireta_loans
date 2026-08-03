// lib/core/network/dio_client.dart
import 'package:dio/dio.dart';

import '../config/env_config.dart';
import '../constants/app_constants.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/error_interceptor.dart';
import 'interceptors/logging_interceptor.dart';

class DioClient {
  late final Dio _dio;

  DioClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: '${EnvConfig.edgeFunctionsUrl}/',
        connectTimeout: const Duration(
          milliseconds: AppConstants.connectTimeoutMs,
        ),
        receiveTimeout: const Duration(
          milliseconds: AppConstants.receiveTimeoutMs,
        ),
        sendTimeout: const Duration(milliseconds: AppConstants.sendTimeoutMs),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          // Required by Supabase gateway to identify your project.
          // Must be present on EVERY request regardless of auth state.
          'apikey': EnvConfig.supabaseAnonKey,
        },
      ),
    );

    // ── Interceptor execution order ────────────────────────────────────────
    // Dio calls onRequest in REGISTRATION order (0 → 1 → 2).
    // Dio calls onError  in REVERSE order       (2 → 1 → 0).
    //
    // Registration order: [Auth(0), Error(1), Logging(2)]
    //   onRequest:  Auth → Error (noop) → Logging   (adds auth header first)
    //   onError:    Logging → Error → Auth            (wraps error, then refreshes)
    //
    // LoggingInterceptor therefore sees the RAW Dio error before ErrorInterceptor
    // wraps it. That is intentional: it lets us log the original transport-level
    // detail even if ErrorInterceptor later converts it to a friendly message.
    // After the ErrorInterceptor fix, err.message is always set, so the log line
    // is readable regardless of which interceptor runs first.
    _dio.interceptors.addAll([
      AuthInterceptor(_dio),
      ErrorInterceptor(),
      if (EnvConfig.isDevelopment) LoggingInterceptor(),
    ]);
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParams}) async {
    return _dio.get(path, queryParameters: queryParams);
  }

  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, String>? headers,
  }) async {
    return _dio.post(
      path,
      data: data,
      options: Options(headers: headers),
    );
  }

  Future<Response> patch(
    String path, {
    dynamic data,
    Map<String, String>? headers,
  }) async {
    return _dio.patch(
      path,
      data: data,
      options: Options(headers: headers),
    );
  }

  Future<Response> delete(String path, {dynamic data}) async {
    return _dio.delete(path, data: data);
  }

  Future<Response> postWithIdempotency(
    String path, {
    required dynamic data,
    required String idempotencyKey,
  }) async {
    return _dio.post(
      path,
      data: data,
      options: Options(headers: {'x-idempotency-key': idempotencyKey}),
    );
  }
}
