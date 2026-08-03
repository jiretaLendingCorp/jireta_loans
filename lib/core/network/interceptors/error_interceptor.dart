// lib/core/network/interceptors/error_interceptor.dart
import 'package:dio/dio.dart';

import '../../errors/app_exception.dart';

class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;

    if (response != null) {
      // ── HTTP-level errors (server returned a response) ──────────────────
      final data = response.data;
      final message = _extractMessage(data);
      final code = _extractCode(data);
      switch (response.statusCode) {
        case 401:
          if (code == 'ACCOUNT_SUSPENDED') {
            return handler.reject(DioException(
              requestOptions: err.requestOptions,
              error: const AccountSuspendedException(),
              response: response,
            ));
          }
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            error: UnauthorizedException(message),
            response: response,
          ));
        case 403:
          if (code == 'ACCOUNT_SUSPENDED') {
            return handler.reject(DioException(
              requestOptions: err.requestOptions,
              error: const AccountSuspendedException(),
              response: response,
            ));
          }
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            error: ForbiddenException(message),
            response: response,
          ));
        case 429:
          if (code == 'ACCOUNT_LOCKED') {
            return handler.reject(DioException(
              requestOptions: err.requestOptions,
              error: AccountLockedException(message),
              response: response,
            ));
          }
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            error: const RateLimitException(),
            response: response,
          ));
        case 422:
        case 400:
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            error: ValidationException(message),
            response: response,
          ));
        case 500:
        case 502:
        case 503:
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            error: const ServerException(),
            response: response,
          ));
      }
    } else {
      // ── Connection-level errors (no HTTP response received) ─────────────
      // Previously these fell through with err.message = null, producing
      // the "[ERR] null <endpoint>: null" log and unhandled DioExceptions.
      switch (err.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            error: const TimeoutException('Request timed out. Please try again.'),
            type: err.type,
          ));
        case DioExceptionType.connectionError:
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            error: const NetworkException('No internet connection.'),
            type: err.type,
          ));
        case DioExceptionType.unknown:
        default:
          // This covers CORS failures on web, DNS errors, and any other
          // transport-level issue where Dio has no HTTP response to inspect.
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            error: NetworkException(
              err.message?.isNotEmpty == true
                  ? err.message!
                  : 'Unable to reach server. Check your connection or verify the function is deployed.',
            ),
            type: err.type,
          ));
      }
    }

    handler.next(err);
  }

  String _extractMessage(dynamic data) {
    if (data is Map) {
      return data['error']?['message'] ?? data['message'] ?? 'An error occurred';
    }
    return 'An error occurred';
  }

  String? _extractCode(dynamic data) {
    if (data is Map) return data['error']?['code']?.toString();
    return null;
  }
}
