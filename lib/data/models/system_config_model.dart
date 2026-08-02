// lib/data/models/system_config_model.dart
import '../../domain/entities/system_config_entity.dart';

class SystemConfigModel extends SystemConfigEntity {
  const SystemConfigModel({
    required super.id,
    required super.configKey,
    required super.configValue,
    super.description,
    super.dataType,
    required super.updatedAt,
  });

  factory SystemConfigModel.fromJson(Map<String, dynamic> json) =>
      SystemConfigModel(
        id: json['id'] ?? '',
        configKey: json['config_key'] ?? '',
        configValue: json['config_value'] ?? '',
        description: json['description'],
        dataType: json['data_type'],
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'])
            : DateTime.now(),
      );
}
