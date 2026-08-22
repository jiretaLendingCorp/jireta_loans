// lib/core/errors/app_exception.dart
class AppException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const AppException(this.message, {this.code, this.statusCode});

  @override
  String toString() => 'AppException: $message (code: $code)';
}

class UnauthorizedException extends AppException {
  const UnauthorizedException(
      [super.message = 'Unauthorized', String code = 'UNAUTHORIZED'])
      : super(code: code, statusCode: 401);
}

class ForbiddenException extends AppException {
  const ForbiddenException(
      [super.message = 'Access denied', String code = 'FORBIDDEN'])
      : super(code: code, statusCode: 403);
}

class NotFoundException extends AppException {
  const NotFoundException(
      [super.message = 'Resource not found', String code = 'NOT_FOUND'])
      : super(code: code, statusCode: 404);
}

class ValidationException extends AppException {
  const ValidationException(super.message, [String code = 'VALIDATION_ERROR'])
      : super(code: code, statusCode: 422);
}

class ServerException extends AppException {
  const ServerException(
      [super.message = 'Internal server error', String code = 'SERVER_ERROR'])
      : super(code: code, statusCode: 500);
}

class NetworkException extends AppException {
  const NetworkException([super.message = 'Network connection error'])
      : super(code: 'NETWORK_ERROR');
}

class TimeoutException extends AppException {
  const TimeoutException([super.message = 'Request timed out'])
      : super(code: 'TIMEOUT');
}

class AccountLockedException extends AppException {
  const AccountLockedException(super.message)
      : super(code: 'ACCOUNT_LOCKED', statusCode: 429);
}

class ForcePasswordChangeException extends AppException {
  const ForcePasswordChangeException()
      : super('Password change required', code: 'FORCE_PASSWORD_CHANGE');
}

class RateLimitException extends AppException {
  const RateLimitException()
      : super(
          'Too many requests. Please try again later.',
          code: 'RATE_LIMITED',
          statusCode: 429,
        );
}
