// lib/domain/entities/in_office_application_entity.dart
class InOfficeApplicationEntity {
  final String id;
  final String createdById;
  final String? createdByName;
  final String? lenderId;
  final String? lenderName;
  final String? loanId;
  final String status;
  final int wizardStep;
  final Map<String, dynamic>? step1Data;
  final Map<String, dynamic>? step2Data;
  final Map<String, dynamic>? step3Data;
  final Map<String, dynamic>? step4Data;
  final Map<String, dynamic>? step5Data;
  final DateTime createdAt;
  final DateTime updatedAt;

  const InOfficeApplicationEntity({
    required this.id,
    required this.createdById,
    this.createdByName,
    this.lenderId,
    this.lenderName,
    this.loanId,
    required this.status,
    required this.wizardStep,
    this.step1Data,
    this.step2Data,
    this.step3Data,
    this.step4Data,
    this.step5Data,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isDraft => status == 'draft';
  bool get isSubmitted => status == 'submitted';
  bool get isConverted => status == 'converted';
}
