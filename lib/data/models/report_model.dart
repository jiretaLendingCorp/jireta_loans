// lib/data/models/report_model.dart
import '../../core/utils/helpers.dart';
import '../../core/utils/timezone.dart';
class ReportTemplateModel {
  final String id;
  final String key;
  final String name;
  final String description;
  final String category;
  final bool supportsPdf;
  final bool supportsXlsx;

  const ReportTemplateModel({
    required this.id,
    required this.key,
    required this.name,
    required this.description,
    required this.category,
    required this.supportsPdf,
    required this.supportsXlsx,
  });

  factory ReportTemplateModel.fromJson(Map<String, dynamic> json) =>
      ReportTemplateModel(
        id: json['id'] ?? '',
        key: json['key'] ?? '',
        name: json['name'] ?? '',
        description: json['description'] ?? '',
        category: json['category'] ?? 'general',
        supportsPdf: parseBool(json['supports_pdf'], fallback: true),
        supportsXlsx: parseBool(json['supports_xlsx'], fallback: true),
      );
}

class GeneratedReportModel {
  final String id;
  final String templateKey;
  final String templateName;
  final String format;
  final String? fileUrl;
  final String? generatedBy;
  final Map<String, dynamic>? parameters;
  final DateTime createdAt;

  const GeneratedReportModel({
    required this.id,
    required this.templateKey,
    required this.templateName,
    required this.format,
    this.fileUrl,
    this.generatedBy,
    this.parameters,
    required this.createdAt,
  });

  factory GeneratedReportModel.fromJson(Map<String, dynamic> json) =>
      GeneratedReportModel(
        id: json['id'] ?? '',
        templateKey: json['template_key'] ?? '',
        templateName: json['template_name'] ?? '',
        format: json['format'] ?? 'pdf',
        fileUrl: json['file_url'],
        generatedBy: json['generated_by'],
        parameters: json['parameters'] as Map<String, dynamic>?,
        createdAt: json['created_at'] != null
            ? parseManila(json['created_at'])!
            : DateTime.now(),
      );
}
