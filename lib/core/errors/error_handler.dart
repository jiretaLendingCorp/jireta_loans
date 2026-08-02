// lib/core/errors/error_handler.dart
import 'package:dio/dio.dart';
import 'failure.dart';
import 'app_exception.dart';

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
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return const NetworkFailure(
          'Request timed out. Please check your connection.',
        );
      case DioExceptionType.connectionError:
        return const NetworkFailure('No internet connection.');
      case DioExceptionType.badResponse:
        return _handleResponse(e.response);
      case DioExceptionType.cancel:
        return const UnknownFailure('Request cancelled.');
      default:
        return const NetworkFailure();
    }
  }

  static Failure _handleResponse(Response? response) {
    if (response == null) return const ServerFailure('No response from server');
    final data = response.data;
    final message = _extractMessage(data);
    final code = _extractCode(data);
    switch (response.statusCode) {
      case 400:
        return ValidationFailure(message);
      case 401:
        return AuthFailure(message, code: code ?? 'UNAUTHORIZED');
      case 403:
        return ForbiddenFailure(message);
      case 404:
        return NotFoundFailure(message);
      case 422:
        return ValidationFailure(message);
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
}
