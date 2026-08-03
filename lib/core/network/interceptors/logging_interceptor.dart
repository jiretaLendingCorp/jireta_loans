// lib/core/network/interceptors/logging_interceptor.dart
import 'package:dio/dio.dart';

import '../../utils/logger.dart';

class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    AppLogger.d('[REQ] ${options.method} ${options.path}');
    AppLogger.d('[REQ] Headers: ${options.headers}');
    if (options.data != null) AppLogger.d('[REQ] Body: ${options.data}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    AppLogger.d('[RES] ${response.statusCode} ${response.requestOptions.path}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // FIX: err.message is null for DioExceptionType.unknown — fall back to
    // the wrapped AppException message (set by ErrorInterceptor) or the type name.
    final status = err.response?.statusCode?.toString() ?? 'no-response';
    final appError = err.error; // set by ErrorInterceptor before this runs
    final message = err.message?.isNotEmpty == true
        ? err.message
        : appError?.toString() ?? err.type.name;
    AppLogger.e('[ERR] $status ${err.requestOptions.path}: $message');
    handler.next(err);
  }
}
