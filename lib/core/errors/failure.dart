// lib/core/errors/failure.dart
abstract class Failure {
  final String message;
  final String? code;
  const Failure(this.message, {this.code});
}

class ServerFailure extends Failure {
  const ServerFailure(super.message, {super.code});
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Network connection error'])
      : super(code: 'NETWORK_ERROR');
}

class AuthFailure extends Failure {
  const AuthFailure(super.message, {super.code});
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {String? code})
      : super(code: code ?? 'VALIDATION_ERROR');
}

class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message, {String? code})
      : super(code: code ?? 'NOT_FOUND');
}

class ForbiddenFailure extends Failure {
  const ForbiddenFailure(super.message, {String? code})
      : super(code: code ?? 'FORBIDDEN');
}

class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'An unexpected error occurred', String? code])
      : super(code: code);
}
