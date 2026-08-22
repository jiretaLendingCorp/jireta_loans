// lib/core/errors/error_handler.dart
import 'package:dio/dio.dart';

import 'app_exception.dart';
import 'failure.dart';

class ErrorHandler {
  static Failure handle(dynamic error) {
    if (error is DioException) {
      return _handleDio(error);
    }
    if (error is AppException) {
      return ServerFailure(error.message, code: error.code);
    }
    return UnknownFailure(error?.toString() ?? 'Unknown error');
  }

  static Failure _handleDio(DioException e) {
    // FIX: ErrorInterceptor stores an AppException in e.error AND a human-
    // readable string in e.message. Prefer unwrapping e.error for typed
    // failures; fall back to e.message for a clean user string.
    final inner = e.error;
    if (inner is AppException) {
      return _fromAppException(inner);
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return NetworkFailure(
          e.message ?? 'Request timed out. Please check your connection.',
        );
      case DioExceptionType.connectionError:
        return NetworkFailure(e.message ?? 'No internet connection.');
      case DioExceptionType.badResponse:
        return _handleResponse(e.response);
      case DioExceptionType.cancel:
        return const UnknownFailure('Request cancelled.');
      case DioExceptionType.unknown:
      default:
        // e.message is now always set by ErrorInterceptor (previously was null).
        // Strip a possible "DioException [...]" prefix so users never see it.
        final msg = _cleanMessage(
          e.message ?? 'Cannot connect to server. Please try again.',
        );
        return NetworkFailure(msg);
    }
  }

  static Failure _fromAppException(AppException e) {
    if (e is UnauthorizedException) return AuthFailure(e.message, code: e.code);
    if (e is ForbiddenException) return ForbiddenFailure(e.message, code: e.code);
    if (e is ValidationException) return ValidationFailure(e.message, code: e.code);
    if (e is NotFoundException) return NotFoundFailure(e.message, code: e.code);
    if (e is NetworkException) return NetworkFailure(e.message);
    if (e is TimeoutException) return NetworkFailure(e.message);
    if (e is AccountLockedException) {
      return AuthFailure(e.message, code: e.code);
    }
    if (e is RateLimitException) {
      return const AuthFailure(
        'Too many requests. Please try again.',
        code: 'RATE_LIMITED',
      );
    }
    return ServerFailure(e.message, code: e.code);
  }

  static Failure _handleResponse(Response? response) {
    if (response == null) return const ServerFailure('No response from server');
    final data = response.data;
    final message = _extractMessage(data);
    final code = _extractCode(data);
    switch (response.statusCode) {
      case 400:
        return ValidationFailure(message, code: code);
      case 401:
        return AuthFailure(message, code: code ?? 'UNAUTHORIZED');
      case 403:
        return ForbiddenFailure(message, code: code);
      case 404:
        return NotFoundFailure(message, code: code);
      case 409:
        // Collection request conflict — preserve ALREADY_IN_PROGRESS etc.
        return ServerFailure(message, code: code ?? 'CONFLICT');
      case 422:
        return ValidationFailure(message, code: code);
      case 429:
        return const AuthFailure(
          'Too many requests. Please try again.',
          code: 'RATE_LIMITED',
        );
      case 500:
      case 502:
      case 503:
        return ServerFailure(message, code: code);
      default:
        return ServerFailure(message, code: code);
    }
  }

  static String _extractMessage(dynamic data) {
    if (data is Map) {
      return data['error']?['message'] ??
          data['message'] ??
          'An error occurred';
    }
    return 'An error occurred';
  }

  static String? _extractCode(dynamic data) {
    if (data is Map) {
      return data['error']?['code']?.toString();
    }
    return null;
  }

  /// Removes the raw "DioException [type]:" prefix that would otherwise leak
  /// into user-facing messages when a DioException escapes unwrapped.
  static String _cleanMessage(String msg) {
    final idx = msg.indexOf('DioException');
    if (idx >= 0) {
      final after = msg.substring(idx).split(':').skip(1).join(':').trim();
      return after.isNotEmpty ? after : msg;
    }
    return msg;
  }
}
