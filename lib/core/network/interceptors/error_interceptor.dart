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
              message: 'Your account has been suspended.',
              error: const AccountSuspendedException(),
              response: response,
            ));
          }
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: message,
            error: UnauthorizedException(message),
            response: response,
          ));
        case 403:
          if (code == 'ACCOUNT_SUSPENDED') {
            return handler.reject(DioException(
              requestOptions: err.requestOptions,
              message: 'Your account has been suspended.',
              error: const AccountSuspendedException(),
              response: response,
            ));
          }
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: message,
            error: ForbiddenException(message),
            response: response,
          ));
        case 429:
          if (code == 'ACCOUNT_LOCKED') {
            return handler.reject(DioException(
              requestOptions: err.requestOptions,
              message: message,
              error: AccountLockedException(message),
              response: response,
            ));
          }
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: 'Too many requests. Please try again later.',
            error: const RateLimitException(),
            response: response,
          ));
        case 422:
        case 400:
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: message,
            error: ValidationException(message),
            response: response,
          ));
        case 500:
        case 502:
        case 503:
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: message.isNotEmpty ? message : 'Internal server error.',
            error: ServerException(message),
            response: response,
          ));
      }
    } else {
      // ── Connection-level errors (no HTTP response received) ─────────────
      // FIX: Every DioException reject now sets both `message:` AND `error:`.
      // Previously `message` was never set, so DioException.toString() always
      // produced "DioException [unknown]: null" — the literal word "null" —
      // which propagated verbatim into every provider's state.error via
      // e.toString(). Now message holds a human-readable string so
      // DioException.toString() is clean even before AppErrorHelper is applied.
      switch (err.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          const timeoutMsg = 'Request timed out. Please try again.';
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: timeoutMsg,
            error: const TimeoutException(timeoutMsg),
            type: err.type,
          ));
        case DioExceptionType.connectionError:
          const noNetMsg = 'No internet connection.';
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: noNetMsg,
            error: const NetworkException(noNetMsg),
            type: err.type,
          ));
        case DioExceptionType.unknown:
        default:
          // Covers CORS failures on web, DNS errors, and any other
          // transport-level failure where Dio has no HTTP response.
          // The most common real-world cause: the Supabase Edge Functions
          // have not been deployed yet (`supabase functions deploy --all`).
          final msg = err.message?.isNotEmpty == true
              ? err.message!
              : 'Unable to reach server. Check your connection or verify the function is deployed.';
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: msg,
            error: NetworkException(msg),
            type: err.type,
          ));
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
