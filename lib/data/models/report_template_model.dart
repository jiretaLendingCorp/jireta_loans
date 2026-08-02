// lib/data/models/report_template_model.dart
class ReportTemplateModel {
  final String id;
  final String templateKey;
  final String name;
  final String description;
  final bool supportsPdf;
  final bool supportsXlsx;
  final List<String> availableFilters;

  const ReportTemplateModel({
    required this.id,
    required this.templateKey,
    required this.name,
    required this.description,
    required this.supportsPdf,
    required this.supportsXlsx,
    required this.availableFilters,
  });

  factory ReportTemplateModel.fromJson(Map<String, dynamic> json) =>
      ReportTemplateModel(
        id: json['id'] ?? '',
        templateKey: json['template_key'] ?? '',
        name: json['name'] ?? '',
        description: json['description'] ?? '',
        supportsPdf: json['supports_pdf'] ?? true,
        supportsXlsx: json['supports_xlsx'] ?? true,
        availableFilters:
            (json['available_filters'] as List?)?.cast<String>() ?? [],
      );
}
