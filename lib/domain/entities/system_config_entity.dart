// lib/domain/entities/system_config_entity.dart
class SystemConfigEntity {
  final String id;
  final String configKey;
  final String configValue;
  final String? description;
  final String? dataType;
  final DateTime updatedAt;

  const SystemConfigEntity({
    required this.id,
    required this.configKey,
    required this.configValue,
    this.description,
    this.dataType,
    required this.updatedAt,
  });
}
