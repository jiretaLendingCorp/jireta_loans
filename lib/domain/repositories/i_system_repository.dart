// lib/domain/repositories/i_system_repository.dart
abstract class ISystemRepository {
  Future<List<dynamic>> getSystemConfig();

  /// Min/max loan amount at interest rate mula sa System Settings — ginagamit
  /// ng Apply Loan at In-Office wizard.
  Future<Map<String, dynamic>> getLoanSettings();
  Future<void> updateSystemConfig(String configKey, String configValue);
  Future<List<dynamic>> getSmsTemplates();
  Future<void> updateSmsTemplate(String templateId, String content);
}
