// lib/domain/repositories/i_system_repository.dart
abstract class ISystemRepository {
  Future<List<dynamic>> getSystemConfig();
  Future<void> updateSystemConfig(String configKey, String configValue);
  Future<List<dynamic>> getSmsTemplates();
  Future<void> updateSmsTemplate(String templateId, String content);
}
