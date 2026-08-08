// lib/data/models/kyc_document_model.dart
class KycDocumentModel {
  final String id;
  final String lenderId;
  final String documentType;
  final String? fileUrl;
  final String status;
  final String? rejectionNotes;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final Map<String, dynamic>? lender;
  final int documentCount;
  final List<String> documentTypes;

  const KycDocumentModel({
    required this.id,
    required this.lenderId,
    required this.documentType,
    this.fileUrl,
    required this.status,
    this.rejectionNotes,
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
    this.lender,
    this.documentCount = 0,
    this.documentTypes = const [],
  });

  factory KycDocumentModel.fromJson(Map<String, dynamic> json) =>
      KycDocumentModel(
        id: json['id'] ?? '',
        lenderId: json['lender_id'] ?? '',
        documentType: json['document_type'] ?? '',
        fileUrl: json['file_url'],
        status: json['status'] ?? 'pending',
        rejectionNotes: json['rejection_notes'],
        reviewedBy: json['reviewed_by'],
        reviewedAt: json['reviewed_at'] != null
            ? DateTime.parse(json['reviewed_at'])
            : null,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'])
            : DateTime.now(),
        lender: json['lender'] as Map<String, dynamic>?,
        documentCount: (json['document_count'] as num?)?.toInt() ?? 0,
        documentTypes: (json['document_types'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
      );

  String get documentCountLabel => documentCount <= 0
      ? 'KYC Submission'
      : documentCount == 1
          ? '1 document'
          : '$documentCount documents';

  String get lenderName {
    if (lender == null) return '';
    return '${lender!['first_name'] ?? ''} ${lender!['last_name'] ?? ''}'
        .trim();
  }

  String get statusLabel {
    switch (status) {
      case 'submitted':
        return 'Submitted';
      case 'verified':
        return 'Verified';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Pending';
    }
  }

  DateTime get submittedAt => createdAt;
}

class KycStatusModel {
  final String lenderId;
  final String kycStatus;
  final List<KycDocumentModel> documents;

  const KycStatusModel({
    required this.lenderId,
    required this.kycStatus,
    required this.documents,
  });

  factory KycStatusModel.fromJson(Map<String, dynamic> json) => KycStatusModel(
    lenderId: json['lender_id'] ?? '',
    kycStatus: json['kyc_status'] ?? 'not_submitted',
    documents: (json['documents'] as List? ?? [])
        .map((e) => KycDocumentModel.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  bool get isNotEmpty => documents.isNotEmpty;
  bool get isEmpty => documents.isEmpty;
  KycDocumentModel get first => documents.first;
}
