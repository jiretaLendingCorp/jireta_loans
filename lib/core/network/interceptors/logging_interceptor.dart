// lib/core/network/interceptors/logging_interceptor.dart
import 'package:dio/dio.dart';

import '../../utils/logger.dart';

class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final q = options.queryParameters.isNotEmpty ? ' query=${options.queryParameters}' : '';
    AppLogger.d('[REQ] ${options.method} ${options.uri}$q');
    // Mask Authorization header value for security (log presence only)
    final headersForLog = Map<String, dynamic>.from(options.headers);
    if (headersForLog.containsKey('Authorization')) {
      final v = headersForLog['Authorization']?.toString() ?? '';
      headersForLog['Authorization'] = v.length > 20 ? '${v.substring(0, 20)}...' : '***';
    }
    AppLogger.d('[REQ] Headers: $headersForLog');
    if (options.data != null) {
      final bodyStr = options.data.toString();
      AppLogger.d('[REQ] Body: ${bodyStr.length > 800 ? "${bodyStr.substring(0, 800)}... (${bodyStr.length} chars)" : bodyStr}');
    }
    options.extra['startTime'] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final start = response.requestOptions.extra['startTime'] as DateTime?;
    final ms = start != null ? DateTime.now().difference(start).inMilliseconds : null;
    final timing = ms != null ? ' (${ms}ms)' : '';
    final dataStr = response.data?.toString() ?? 'null';
    AppLogger.d('[RES] ${response.statusCode} ${response.requestOptions.path}$timing');
    if (dataStr.length > 1200) {
      AppLogger.d('[RES] Body: ${dataStr.substring(0, 1200)}... (${dataStr.length} chars)');
    } else {
      AppLogger.d('[RES] Body: $dataStr');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode?.toString() ?? 'no-response';
    final message = err.message?.isNotEmpty == true
        ? err.message
        : err.error?.toString() ?? err.type.name;
    final start = err.requestOptions.extra['startTime'] as DateTime?;
    final ms = start != null ? DateTime.now().difference(start).inMilliseconds : null;
    final timing = ms != null ? ' (${ms}ms)' : '';
    final respData = err.response?.data?.toString();
    AppLogger.e(
      '[ERR] $status ${err.requestOptions.uri}$timing: $message\n'
      '      type=${err.type}, data=${respData != null && respData.length > 800 ? "${respData.substring(0, 800)}..." : respData}',
    );
    handler.next(err);
  }
}
