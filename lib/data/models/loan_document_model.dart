// lib/data/models/loan_document_model.dart
class LoanDocumentModel {
  final String id;
  final String loanId;
  final String lenderId;
  final String documentType;
  final String fileUrl;
  final String status;
  final DateTime createdAt;

  const LoanDocumentModel({
    required this.id,
    required this.loanId,
    required this.lenderId,
    required this.documentType,
    required this.fileUrl,
    required this.status,
    required this.createdAt,
  });

  factory LoanDocumentModel.fromJson(Map<String, dynamic> json) {
    return LoanDocumentModel(
      id: json['id'] ?? '',
      loanId: json['loan_id'] ?? '',
      lenderId: json['lender_id'] ?? '',
      documentType: json['document_type'] ?? '',
      fileUrl: json['file_url'] ?? '',
      status: json['status'] ?? 'pending',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'loan_id': loanId,
        'lender_id': lenderId,
        'document_type': documentType,
        'file_url': fileUrl,
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };
}
