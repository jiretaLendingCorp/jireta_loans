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
    // NOTE ON INTERCEPTOR ORDER: Dio calls onError in REVERSE registration
    // order. DioClient registers interceptors as [Auth, Error, Logging], so
    // for errors the chain is: Logging → Error → Auth.
    // This means the LoggingInterceptor sees the RAW Dio error BEFORE
    // ErrorInterceptor has wrapped it into an AppException.
    // After this fix, ErrorInterceptor always sets err.message so the log
    // line is clean even for the initial raw error pass.
    final status = err.response?.statusCode?.toString() ?? 'no-response';
    final message = err.message?.isNotEmpty == true
        ? err.message
        : err.error?.toString() ?? err.type.name;
    AppLogger.e('[ERR] $status ${err.requestOptions.path}: $message');
    handler.next(err);
  }
}
