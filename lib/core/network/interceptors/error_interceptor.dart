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
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: message,
            error: UnauthorizedException(message, code ?? 'UNAUTHORIZED'),
            response: response,
            type: err.type,
          ));
        case 403:
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: message,
            error: ForbiddenException(message, code ?? 'FORBIDDEN'),
            response: response,
            type: err.type,
          ));
        case 429:
          if (code == 'ACCOUNT_LOCKED' || code == 'OTP_LOCKED') {
            return handler.reject(DioException(
              requestOptions: err.requestOptions,
              message: message,
              error: AccountLockedException(message),
              response: response,
              type: err.type,
            ));
          }
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: message.isNotEmpty
                ? message
                : 'Too many requests. Please try again later.',
            error: const RateLimitException(),
            response: response,
            type: err.type,
          ));
        case 422:
        case 400:
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: message,
            error: ValidationException(message, code ?? 'VALIDATION_ERROR'),
            response: response,
            type: err.type,
          ));
        case 404:
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: message.isNotEmpty ? message : 'Not found.',
            error: NotFoundException(
                message.isNotEmpty ? message : 'Not found.',
                code ?? 'NOT_FOUND'),
            response: response,
            type: err.type,
          ));
        case 409:
          // Collection request conflict e.g. Already pending payment.
          // Preserve server code ALREADY_IN_PROGRESS so the provider can
          // distinguish it from generic conflicts.
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: message.isNotEmpty ? message : 'Conflict.',
            error: AppException(
                message.isNotEmpty ? message : 'Conflict.',
                code: code ?? 'CONFLICT',
                statusCode: 409),
            response: response,
            type: err.type,
          ));
        case 500:
        case 502:
        case 503:
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: message.isNotEmpty ? message : 'Internal server error.',
            error: ServerException(
                message.isNotEmpty ? message : 'Internal server error.',
                code ?? 'SERVER_ERROR'),
            response: response,
            type: err.type,
          ));
        // FIX: Any OTHER HTTP status (404, 408, 429-without-code, 451, etc.)
        // previously fell through to `handler.next(err)` and reached the UI as
        // the RAW DioException with a null message ("DioException [badResponse]:
        // null"). Wrap every response here so a friendly message always surfaces.
        default:
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: message.isNotEmpty ? message : 'An error occurred.',
            error: AppException(
                message.isNotEmpty ? message : 'An error occurred.',
                code: code ?? 'BAD_REQUEST',
                statusCode: response.statusCode),
            response: response,
            type: err.type,
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
          // have not been deployed yet (`supabase functions deploy --all`),
          // or the host in EDGE_FUNCTIONS_URL is unreachable.
          final msg = _describeUnknownError(err);
          return handler.reject(DioException(
            requestOptions: err.requestOptions,
            message: msg,
            error: NetworkException(msg),
            type: err.type,
          ));
      }
    }
  }

  String _extractMessage(dynamic data) {
    if (data is Map) {
      return data['error']?['message'] ??
          data['message'] ??
          'An error occurred';
    }
    return 'An error occurred';
  }

  /// Builds a stable, human-readable message for transport-level failures
  /// (DioExceptionType.unknown). The raw `err.message` is frequently null or a
  /// platform-specific blob, so we inspect the wrapped `err.error` (SocketException,
  /// HandshakeException, ClientException, ...) and always fall back to the same
  /// friendly "cannot reach server" sentence. This guarantees the UI never shows
  /// a bare "DioException [unknown]: null".
  String _describeUnknownError(DioException err) {
    final raw = err.message;
    if (raw != null && raw.isNotEmpty && !raw.contains('DioException')) {
      return raw;
    }
    final cause = err.error;
    final causeText = cause?.toString() ?? '';
    if (causeText.contains('SocketException')) {
      return 'Unable to reach server. Please check your connection.';
    }
    if (causeText.contains('HandshakeException')) {
      return 'Secure connection failed. Please try again.';
    }
    if (causeText.contains('ClientException') ||
        causeText.contains('Failed host lookup') ||
        causeText.contains('Connection refused')) {
      return 'Unable to reach server. Check your connection or verify the function is deployed.';
    }
    return 'Unable to reach server. Check your connection or verify the function is deployed.';
  }

  String? _extractCode(dynamic data) {
    if (data is Map) return data['error']?['code']?.toString();
    return null;
  }
}
