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
    AppLogger.e(
      '[ERR] ${err.response?.statusCode} ${err.requestOptions.path}: ${err.message}',
    );
    handler.next(err);
  }
}
