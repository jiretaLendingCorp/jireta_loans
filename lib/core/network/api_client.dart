// lib/core/network/api_client.dart
abstract class ApiClient {
  Future<dynamic> get(
    String endpoint, {
    Map<String, dynamic>? queryParams,
  });

  Future<dynamic> post(
    String endpoint, {
    Map<String, dynamic>? body,
  });

  Future<dynamic> patch(
    String endpoint, {
    Map<String, dynamic>? body,
  });

  Future<dynamic> delete(
    String endpoint, {
    Map<String, dynamic>? queryParams,
  });
}
