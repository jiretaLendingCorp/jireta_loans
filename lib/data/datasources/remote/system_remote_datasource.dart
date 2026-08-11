// lib/data/datasources/remote/system_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';

class SystemRemoteDataSource {
  final DioClient _client;
  SystemRemoteDataSource(this._client);

  Future<List<dynamic>> getSystemConfig() async {
    final res = await _client.get(ApiEndpoints.systemGetConfig);
    return (res.data['configs'] as List?) ?? [];
  }

  Future<void> updateSystemConfig(String configKey, String configValue) async {
    await _client.patch(ApiEndpoints.systemUpdateConfig, data: {
      'config_key': configKey,
      'config_value': configValue,
    });
  }

  Future<List<dynamic>> getSmsTemplates() async {
    final res = await _client.get(ApiEndpoints.systemGetSmsTemplates);
    return (res.data['templates'] as List?) ?? [];
  }

  Future<void> updateSmsTemplate(String templateId, String content) async {
    await _client.patch(ApiEndpoints.systemUpdateSmsTemplate, data: {
      'template_id': templateId,
      'content': content,
    });
  }
}
