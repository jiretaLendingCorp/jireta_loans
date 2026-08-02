// lib/core/constants/api_constants.dart
class ApiConstants {
  ApiConstants._();

  static const int connectTimeoutMs = 30000;
  static const int receiveTimeoutMs = 30000;
  static const int sendTimeoutMs = 30000;
  static const int maxRetries = 1;

  static const String contentTypeJson = 'application/json';
  static const String authBearer = 'Bearer';
  static const String authorizationHeader = 'Authorization';
  static const String contentTypeHeader = 'Content-Type';
}
