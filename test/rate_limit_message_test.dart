// test/rate_limit_message_test.dart
//
// REGRESSION: ang 429 mula sa Edge Function ay madalas na may MAHALAGANG
// detalye sa mensahe nito — hal. ang GCash link limit ng lender:
//
//   "You've reached the limit of 3 GCash links for this installment. Please
//    try again in about 30 minute(s) — or pay via Cash on Delivery in the
//    meantime."
//
// Dating pinapalitan ito ng generic na "Too many requests. Please try again."
// ng ErrorInterceptor/ErrorHandler, kaya ang lender na naka-block sa GCash ay
// walang clue kung gaano katagal maghintay o ano ang alternatibong bayaran.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jireta_loans/core/errors/app_exception.dart';
import 'package:jireta_loans/core/errors/error_handler.dart';
import 'package:jireta_loans/core/errors/failure.dart';
import 'package:jireta_loans/core/network/interceptors/error_interceptor.dart';

const String _serverMessage =
    "You've reached the limit of 3 GCash links for this installment. "
    'Please try again in about 30 minute(s) — or pay via Cash on Delivery in '
    'the meantime.';

/// Adapter na agad na nagbabalik ng nakapirming status/body — walang network.
class _StaticAdapter implements HttpClientAdapter {
  _StaticAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        body,
        statusCode,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

DioException _dio429({Map<String, dynamic>? body}) => DioException(
      requestOptions: RequestOptions(path: '/payments-xendit-link'),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: '/payments-xendit-link'),
        statusCode: 429,
        data: body,
      ),
      type: DioExceptionType.badResponse,
    );

void main() {
  group('429 message propagation', () {
    test('ErrorHandler: ang 429 message ng server ay hindi pinapalitan', () {
      final failure = ErrorHandler.handle(_dio429(body: {
        'error': {
          'message': _serverMessage,
          'code': 'PAYMENT_ATTEMPT_BLOCKED',
        },
      }));
      expect(failure.message, _serverMessage);
      expect(failure.code, 'PAYMENT_ATTEMPT_BLOCKED');
    });

    test('ErrorHandler: may fallback kapag blangko o placeholder ang body', () {
      for (final body in <Map<String, dynamic>?>[null, const {}]) {
        final failure = ErrorHandler.handle(_dio429(body: body));
        expect(failure.message, contains('Too many requests'),
            reason: 'body=$body');
        expect(failure.code, 'RATE_LIMITED');
      }
    });

    test('ErrorInterceptor: RateLimitException ay may server message', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..interceptors.add(ErrorInterceptor())
        ..httpClientAdapter = _StaticAdapter(
          429,
          jsonEncode({
            'error': {
              'message': _serverMessage,
              'code': 'PAYMENT_ATTEMPT_BLOCKED',
            },
          }),
        );

      try {
        await dio.post<dynamic>('/payments-xendit-link?fn=generate');
        fail('dapat nag-throw ng DioException para sa 429');
      } on DioException catch (e) {
        expect(e.error, isA<RateLimitException>());
        expect((e.error! as RateLimitException).message, _serverMessage);
        // Ang lender-facing string (ginagamit ng GCash screen) ay galing dito.
        expect(ErrorHandler.handle(e).message, _serverMessage);
        expect(ErrorHandler.handle(e).code, 'PAYMENT_ATTEMPT_BLOCKED');
      }
    });

    test('ErrorInterceptor: fallback kapag blangko ang 429 body', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..interceptors.add(ErrorInterceptor())
        ..httpClientAdapter = _StaticAdapter(429, '');

      try {
        await dio.post<dynamic>('/payments-xendit-link?fn=generate');
        fail('dapat nag-throw ng DioException para sa 429');
      } on DioException catch (e) {
        final failure = ErrorHandler.handle(e);
        expect(failure, isA<Failure>());
        expect(failure.message, contains('Too many requests'));
      }
    });
  });
}
