// lib/data/models/credit_investigation_model.dart
class CreditInvestigationModel {
  final String id;
  final String loanId;
  final String? riderId;
  final String? assignedBy;
  final String status;
  final String? investigationNotes;
  final String? reportSummary;
  final DateTime? deadline;
  final DateTime? responseAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final Map<String, dynamic>? loan;
  final Map<String, dynamic>? rider;
  final Map<String, dynamic>? assignedByUser;
  final List<Map<String, dynamic>>? documents;

  const CreditInvestigationModel({
    required this.id,
    required this.loanId,
    this.riderId,
    this.assignedBy,
    required this.status,
    this.investigationNotes,
    this.reportSummary,
    this.deadline,
    this.responseAt,
    this.completedAt,
    required this.createdAt,
    this.loan,
    this.rider,
    this.assignedByUser,
    this.documents,
  });

  factory CreditInvestigationModel.fromJson(Map<String, dynamic> json) =>
      CreditInvestigationModel(
        id: json['id'] ?? '',
        loanId: json['loan_id'] ?? '',
        riderId: json['rider_id'],
        assignedBy: json['assigned_by'],
        status: json['status'] ?? 'pending',
        investigationNotes: json['investigation_notes'],
        reportSummary: json['report_summary'],
        deadline: json['deadline'] != null
            ? DateTime.parse(json['deadline'])
            : null,
        responseAt: json['response_at'] != null
            ? DateTime.parse(json['response_at'])
            : null,
        completedAt: json['completed_at'] != null
            ? DateTime.parse(json['completed_at'])
            : null,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'])
            : DateTime.now(),
        loan: json['loan'] as Map<String, dynamic>?,
        rider: json['rider'] as Map<String, dynamic>?,
        assignedByUser:
            json['assigner'] as Map<String, dynamic>? ??
            json['assigned_by_user'] as Map<String, dynamic>?,
        documents: (json['documents'] as List?)?.cast<Map<String, dynamic>>(),
      );

  String get loanNumber => loan?['loan_number'] ?? '';
  String get lenderName {
    final l = loan?['users'] ?? loan?['lender'];
    if (l == null) return '';
    return '${l['first_name'] ?? ''} ${l['last_name'] ?? ''}'.trim();
  }

  Map<String, dynamic>? get _borrower {
    final b = loan?['users'];
    if (b is Map) return Map<String, dynamic>.from(b);
    final l = loan?['lender'];
    if (l is Map) return Map<String, dynamic>.from(l);
    return null;
  }

  String get borrowerName {
    final b = _borrower;
    if (b == null) return '';
    return '${b['first_name'] ?? ''} ${b['last_name'] ?? ''}'.trim();
  }

  String get borrowerPhone =>
      (_borrower?['phone'] as String?) ?? (_borrower?['phone_number'] as String?) ?? '';

  String get borrowerAddress {
    final a = loan?['address'];
    if (a == null) return '';
    if (a is Map) {
      final street = a['street'] ?? '';
      final city = a['city'] ?? '';
      final province = a['province'] ?? '';
      return [street, city, province]
          .where((e) => e.toString().isNotEmpty)
          .join(', ');
    }
    return a.toString();
  }

  DateTime get assignedAt => createdAt;

  String get riderName {
    if (rider == null) return '';
    return '${rider!['first_name'] ?? ''} ${rider!['last_name'] ?? ''}'.trim();
  }

  String get assignedByName {
    if (assignedByUser == null) return '';
    return '${assignedByUser!['first_name'] ?? ''} ${assignedByUser!['last_name'] ?? ''}'
        .trim();
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'declined':
        return 'Declined';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
  }
}
