// lib/data/repositories/system_repository_impl.dart
import '../../domain/repositories/i_system_repository.dart';
import '../datasources/remote/system_remote_datasource.dart';

class SystemRepositoryImpl implements ISystemRepository {
  final SystemRemoteDataSource _ds;
  SystemRepositoryImpl(this._ds);

  @override
  Future<List<dynamic>> getSystemConfig() => _ds.getSystemConfig();

  @override
  Future<void> updateSystemConfig(String configKey, String configValue) =>
      _ds.updateSystemConfig(configKey, configValue);

  @override
  Future<List<dynamic>> getSmsTemplates() => _ds.getSmsTemplates();

  @override
  Future<void> updateSmsTemplate(String templateId, String content) =>
      _ds.updateSmsTemplate(templateId, content);
}
