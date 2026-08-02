// lib/domain/entities/report_entity.dart
class ReportEntity {
  final String id;
  final String templateKey;
  final String templateName;
  final String generatedById;
  final String? generatedByName;
  final Map<String, dynamic>? parameters;
  final String? pdfUrl;
  final String? xlsxUrl;
  final String status;
  final DateTime createdAt;

  const ReportEntity({
    required this.id,
    required this.templateKey,
    required this.templateName,
    required this.generatedById,
    this.generatedByName,
    this.parameters,
    this.pdfUrl,
    this.xlsxUrl,
    required this.status,
    required this.createdAt,
  });
}
