// lib/data/models/sms_template_model.dart
import '../../core/utils/helpers.dart';
import '../../core/utils/timezone.dart';
class SmsTemplateModel {
  final String id;
  final String key;
  final String name;
  final String body;
  final List<String> variables;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SmsTemplateModel({
    required this.id,
    required this.key,
    required this.name,
    required this.body,
    required this.variables,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SmsTemplateModel.fromJson(Map<String, dynamic> json) {
    return SmsTemplateModel(
      id: json['id'] ?? '',
      key: json['key'] ?? '',
      name: json['name'] ?? '',
      body: json['body'] ?? '',
      variables: (json['variables'] as List?)?.cast<String>() ?? [],
      isActive: parseBool(json['is_active'], fallback: true),
      createdAt: json['created_at'] != null
          ? parseManila(json['created_at'])!
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'key': key,
        'name': name,
        'body': body,
        'variables': variables,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
