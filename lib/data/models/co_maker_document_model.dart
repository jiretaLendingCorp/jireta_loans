// lib/data/models/co_maker_document_model.dart
import '../../core/utils/timezone.dart';

class CoMakerDocumentModel {
  final String id;
  final String coMakerId;
  final String documentType;
  final String fileUrl;
  final String status;
  final DateTime createdAt;

  const CoMakerDocumentModel({
    required this.id,
    required this.coMakerId,
    required this.documentType,
    required this.fileUrl,
    required this.status,
    required this.createdAt,
  });

  factory CoMakerDocumentModel.fromJson(Map<String, dynamic> json) {
    return CoMakerDocumentModel(
      id: json['id'] ?? '',
      coMakerId: json['co_maker_id'] ?? '',
      documentType: json['document_type'] ?? '',
      fileUrl: json['file_url'] ?? '',
      status: json['status'] ?? 'pending',
      createdAt: json['created_at'] != null
          ? parseManila(json['created_at'])!
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'co_maker_id': coMakerId,
        'document_type': documentType,
        'file_url': fileUrl,
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };
}
