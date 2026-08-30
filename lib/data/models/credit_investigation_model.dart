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
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? reviewNotes;
  final String? reviewDecision;
  final Map<String, dynamic>? reviewer;
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
    this.reviewedAt,
    this.reviewedBy,
    this.reviewNotes,
    this.reviewDecision,
    this.reviewer,
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
        deadline:
            json['deadline'] != null ? DateTime.parse(json['deadline']) : null,
        responseAt: json['response_at'] != null
            ? DateTime.parse(json['response_at'])
            : null,
        completedAt: json['completed_at'] != null
            ? DateTime.parse(json['completed_at'])
            : null,
        reviewedAt: json['reviewed_at'] != null
            ? DateTime.parse(json['reviewed_at'])
            : null,
        reviewedBy: json['reviewed_by'] as String?,
        reviewNotes: json['review_notes'] as String?,
        reviewDecision: json['review_decision'] as String?,
        reviewer: json['reviewer'] as Map<String, dynamic>? ??
            json['reviewer_user'] as Map<String, dynamic>?,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'])
            : DateTime.now(),
        loan: json['loan'] as Map<String, dynamic>? ??
            (json['loans'] is Map
                ? (json['loans'] as Map).cast<String, dynamic>()
                : (json['loans'] is List && (json['loans'] as List).isNotEmpty
                    ? (json['loans'] as List).first
                    : null) as Map<String, dynamic>?),
        rider: json['rider'] as Map<String, dynamic>?,
        assignedByUser: json['assigner'] as Map<String, dynamic>? ??
            json['assigned_by_user'] as Map<String, dynamic>?,
        documents: (json['ci_documents'] as List?)?.cast<Map<String, dynamic>>() ??
            (json['documents'] as List?)?.cast<Map<String, dynamic>>(),
      );

  String get loanNumber => loan?['loan_number'] ?? '';
  String get lenderName {
    final b = _borrower;
    if (b == null) return '';
    return '${b['first_name'] ?? ''} ${b['last_name'] ?? ''}'.trim();
  }

  Map<String, dynamic>? get _borrower {
    // ci-get-list embeds the borrower as loans.lender_profile.users.
    final profile = loan?['lender_profile'];
    if (profile is Map) {
      final u = profile['users'];
      if (u is Map) return Map<String, dynamic>.from(u);
      return Map<String, dynamic>.from(profile);
    }
    final lp = loan?['lender_profiles'];
    if (lp is Map) {
      final u = lp['users'];
      if (u is Map) return Map<String, dynamic>.from(u);
      return Map<String, dynamic>.from(lp);
    }
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
      (_borrower?['phone'] as String?) ??
      (_borrower?['phone_number'] as String?) ??
      '';

  String get borrowerAddress {
    final a = loan?['lender_address'] ?? loan?['address'];
    if (a == null) return '';
    if (a is Map) {
      final street = a['street'] ?? '';
      final barangay = a['barangay'] ?? '';
      final city = a['city'] ?? '';
      final province = a['province'] ?? '';
      return [street, barangay, city, province]
          .where((e) => e.toString().isNotEmpty)
          .join(', ');
    }
    return a.toString();
  }

  DateTime get assignedAt => createdAt;

  String get riderName {
    if (rider == null) return '';
    // ci-get-list embeds the rider as rider_profiles(users(first_name, last_name)).
    final r = rider!;
    final nested = r['users'];
    if (nested is Map) {
      return '${nested['first_name'] ?? ''} ${nested['last_name'] ?? ''}'.trim();
    }
    return '${r['first_name'] ?? ''} ${r['last_name'] ?? ''}'.trim();
  }

  String get assignedByName {
    if (assignedByUser == null) return '';
    return '${assignedByUser!['first_name'] ?? ''} ${assignedByUser!['last_name'] ?? ''}'
        .trim();
  }

  String get reviewerName {
    if (reviewer == null) return '';
    return '${reviewer!['first_name'] ?? ''} ${reviewer!['last_name'] ?? ''}'.trim();
  }

  bool get isPendingApproval => status == 'completed';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

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
        return 'Pending Approval';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      default:
        return status;
    }
  }
}
