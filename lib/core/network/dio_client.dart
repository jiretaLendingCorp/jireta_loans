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
