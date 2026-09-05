// lib/data/datasources/remote/device_token_remote_datasource.dart
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';

/// Registers / deactivates this device's FCM token via the device-tokens
/// edge function. All writes go through the authenticated edge function —
/// the Flutter client never touches the user_devices table directly.
class DeviceTokenRemoteDataSource {
  final DioClient _client;
  DeviceTokenRemoteDataSource(this._client);

  Future<void> register({
    required String token,
    required String platform,
    String? appVersion,
  }) async {
    await _client.post(
      ApiEndpoints.deviceTokensRegister,
      data: {
        'fcm_token': token,
        'platform': platform,
        if (appVersion != null) 'app_version': appVersion,
      },
    );
  }

  Future<void> unregister({required String token}) async {
    await _client.post(
      ApiEndpoints.deviceTokensUnregister,
      data: {'fcm_token': token},
    );
  }
}