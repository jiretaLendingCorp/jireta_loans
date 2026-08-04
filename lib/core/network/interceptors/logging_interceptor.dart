// lib/core/network/interceptors/logging_interceptor.dart
import 'package:dio/dio.dart';

import '../../utils/logger.dart';

class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    AppLogger.d('[REQ] ${options.method} ${options.uri}');
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
    final status = err.response?.statusCode?.toString() ?? 'no-response';
    final message = err.message?.isNotEmpty == true
        ? err.message
        : err.error?.toString() ?? err.type.name;
    AppLogger.e(
      '[ERR] $status ${err.requestOptions.uri}: $message\n'
      '      type=${err.type}, response=${err.response != null}',
    );
    handler.next(err);
  }
}
