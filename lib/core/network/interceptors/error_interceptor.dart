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
          // The most common real-world causes:
          // - Supabase Edge Functions have not been deployed yet
          //   (`supabase functions deploy --all`), or host unreachable.
          // - NEW Aug 2026: origin https://jireta.vercel.app not in
          //   CORS_ALLOWED_ORIGINS → browser blocks response → Dio unknown →
          //   previously surfaced as "No internet connection" via the probe.
          //   With the connectivity_service refactor the offline toast no longer
          //   fires for this, but API calls still fail here — surface a CORS
          //   hint so the mis-config is obvious in logs/UI.
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
    final uri = err.requestOptions.uri.toString().toLowerCase();
    final isSupabaseHost = uri.contains('supabase.co');
    if (causeText.contains('SocketException')) {
      if (causeText.contains('Failed host lookup') && isSupabaseHost) {
        return 'Unable to reach server (DNS failed). Verify SUPABASE_URL/EDGE_FUNCTIONS_URL and that the project is not paused.';
      }
      return 'Unable to reach server. Please check your connection.';
    }
    if (causeText.contains('HandshakeException')) {
      return 'Secure connection failed. Please try again.';
    }
    if (causeText.contains('ClientException') ||
        causeText.contains('Failed host lookup') ||
        causeText.contains('Connection refused')) {
      // On web ClientException + "XMLHttpRequest" often means CORS was blocked
      // because the new origin jireta.vercel.app isn't in CORS_ALLOWED_ORIGINS.
      if (causeText.contains('XMLHttpRequest') || causeText.contains('ClientException')) {
        return 'Unable to reach server (network/CORS). If on jireta.vercel.app, check CORS_ALLOWED_ORIGINS includes this origin.';
      }
      return 'Unable to reach server. Check your connection or verify the function is deployed.';
    }
    // Generic fallback — hint at CORS for Supabase hosts on web
    if (isSupabaseHost && causeText.contains('XMLHttpRequest')) {
      return 'Unable to reach server (CORS/network). Verify jireta.vercel.app is allowed in Supabase CORS settings.';
    }
    return 'Unable to reach server. Check your connection or verify the function is deployed.';
  }

  String? _extractCode(dynamic data) {
    if (data is Map) return data['error']?['code']?.toString();
    return null;
  }
}
