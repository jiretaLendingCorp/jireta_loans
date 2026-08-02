// lib/core/network/interceptors/error_interceptor.dart
import 'package:dio/dio.dart';
import '../../errors/app_exception.dart';

class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (response != null) {
      final data = response.data;
      final message = _extractMessage(data);
      final code = _extractCode(data);
      switch (response.statusCode) {
        case 401:
          if (code == 'ACCOUNT_SUSPENDED') {
            return handler.reject(
              DioException(
                requestOptions: err.requestOptions,
                error: const AccountSuspendedException(),
                response: response,
              ),
            );
          }
          return handler.reject(
            DioException(
              requestOptions: err.requestOptions,
              error: UnauthorizedException(message),
              response: response,
            ),
          );
        case 403:
          if (code == 'ACCOUNT_SUSPENDED') {
            return handler.reject(
              DioException(
                requestOptions: err.requestOptions,
                error: const AccountSuspendedException(),
                response: response,
              ),
            );
          }
          return handler.reject(
            DioException(
              requestOptions: err.requestOptions,
              error: ForbiddenException(message),
              response: response,
            ),
          );
        case 429:
          if (code == 'ACCOUNT_LOCKED') {
            return handler.reject(
              DioException(
                requestOptions: err.requestOptions,
                error: AccountLockedException(message),
                response: response,
              ),
            );
          }
          return handler.reject(
            DioException(
              requestOptions: err.requestOptions,
              error: const RateLimitException(),
              response: response,
            ),
          );
        case 422:
        case 400:
          return handler.reject(
            DioException(
              requestOptions: err.requestOptions,
              error: ValidationException(message),
              response: response,
            ),
          );
        case 500:
        case 502:
        case 503:
          return handler.reject(
            DioException(
              requestOptions: err.requestOptions,
              error: const ServerException(),
              response: response,
            ),
          );
      }
    }
    handler.next(err);
  }

  String _extractMessage(dynamic data) {
    if (data is Map) {
      return data['error']?['message'] ??
          data['message'] ??
          'An error occurred';
    }
    return 'An error occurred';
  }

  String? _extractCode(dynamic data) {
    if (data is Map) return data['error']?['code']?.toString();
    return null;
  }
}
