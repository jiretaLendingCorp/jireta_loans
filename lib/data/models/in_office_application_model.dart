// lib/data/models/in_office_application_model.dart
class InOfficeApplicationModel {
  final String id;
  final String status;
  final int wizardStep;
  final String? lenderId;
  final String? loanId;
  final String createdBy;
  final Map<String, dynamic>? step1Data;
  final Map<String, dynamic>? step2Data;
  final Map<String, dynamic>? step3Data;
  final Map<String, dynamic>? step4Data;
  final Map<String, dynamic>? step5Data;
  final String? creatorName;
  final DateTime createdAt;
  final DateTime updatedAt;

  const InOfficeApplicationModel({
    required this.id,
    required this.status,
    required this.wizardStep,
    this.lenderId,
    this.loanId,
    required this.createdBy,
    this.step1Data,
    this.step2Data,
    this.step3Data,
    this.step4Data,
    this.step5Data,
    this.creatorName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InOfficeApplicationModel.fromJson(Map<String, dynamic> json) {
    return InOfficeApplicationModel(
      id: json['id'] ?? '',
      status: json['status'] ?? 'draft',
      wizardStep: (json['wizard_step'] as num?)?.toInt() ?? 1,
      lenderId: json['lender_id'],
      loanId: json['loan_id'],
      createdBy: json['created_by'] ?? '',
      step1Data: json['step1_data'] as Map<String, dynamic>?,
      step2Data: json['step2_data'] as Map<String, dynamic>?,
      step3Data: json['step3_data'] as Map<String, dynamic>?,
      step4Data: json['step4_data'] as Map<String, dynamic>?,
      step5Data: json['step5_data'] as Map<String, dynamic>?,
      creatorName: json['creator']?['first_name'] != null
          ? '${json['creator']['first_name']} ${json['creator']['last_name']}'
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : DateTime.now(),
    );
  }

  bool get isDraft => status == 'draft';
  bool get isSubmitted => status == 'submitted';
  bool get isConverted => status == 'converted';

  String get borrowerName {
    final s = step1Data;
    if (s == null) return 'Unknown';
    return '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'.trim();
  }
}
