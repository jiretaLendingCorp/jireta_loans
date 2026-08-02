// lib/domain/entities/kyc_document_entity.dart
class KycDocumentEntity {
  final String id;
  final String lenderId;
  final String documentType;
  final String fileUrl;
  final String status;
  final String? rejectionNotes;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final DateTime createdAt;

  const KycDocumentEntity({
    required this.id,
    required this.lenderId,
    required this.documentType,
    required this.fileUrl,
    required this.status,
    this.rejectionNotes,
    this.verifiedBy,
    this.verifiedAt,
    required this.createdAt,
  });
}
