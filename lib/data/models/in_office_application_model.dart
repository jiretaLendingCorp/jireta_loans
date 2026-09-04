// lib/data/models/in_office_application_model.dart
import '../../core/utils/timezone.dart';

class InOfficeApplicationModel {
  final String id;
  final String status;
  final int wizardStep;
  final String? lenderId;
  final String? loanId;
  final String createdBy;
  final Map<String, dynamic>? personalInfo;
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
    this.personalInfo,
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
      personalInfo: json['personal_info'] as Map<String, dynamic>?,
      creatorName: json['creator']?['first_name'] != null
          ? '${json['creator']['first_name']} ${json['creator']['last_name']}'
          : null,
      createdAt: json['created_at'] != null
          ? parseManila(json['created_at'])!
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
    final s = personalInfo;
    if (s == null) return 'Unknown';
    return '${s['first_name'] ?? ''} ${s['last_name'] ?? ''}'.trim();
  }
}
