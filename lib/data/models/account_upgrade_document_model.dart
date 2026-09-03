// lib/data/models/account_upgrade_document_model.dart
class AccountUpgradeDocumentModel {
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

  const AccountUpgradeDocumentModel({
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

  factory AccountUpgradeDocumentModel.fromJson(Map<String, dynamic> json) =>
      AccountUpgradeDocumentModel(
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
      ? 'Account Upgrade Submission'
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

class AccountUpgradeStatusModel {
  final String lenderId;
  final String accountUpgradeStatus;
  final List<AccountUpgradeDocumentModel> documents;
  final DateTime? rejectedAt;
  final DateTime? resubmitAfter;
  final int? daysRemaining;
  final bool canResubmit;

  const AccountUpgradeStatusModel({
    required this.lenderId,
    required this.accountUpgradeStatus,
    required this.documents,
    this.rejectedAt,
    this.resubmitAfter,
    this.daysRemaining,
    this.canResubmit = true,
  });

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  factory AccountUpgradeStatusModel.fromJson(Map<String, dynamic> json) {
    DateTime? rejectedAt = _parseDate(json['rejected_at']);
    DateTime? resubmitAfter = _parseDate(json['resubmit_after']);
    int? daysRemaining = (json['days_remaining'] as num?)?.toInt();
    bool canResubmit = json['can_resubmit'] as bool? ?? true;

    final docs = (json['documents'] as List? ?? [])
        .map((e) =>
            AccountUpgradeDocumentModel.fromJson(e as Map<String, dynamic>))
        .toList();

    // Fallback: compute 30-day cooldown locally from latest rejected
    // reviewed_at when backend does not send cooldown fields (old deploy).
    if ((json['account_upgrade_status'] ?? 'not_submitted') == 'rejected' &&
        (rejectedAt == null || resubmitAfter == null)) {
      DateTime? latest;
      for (final d in docs) {
        if (d.status == 'rejected' && d.reviewedAt != null) {
          if (latest == null || d.reviewedAt!.isAfter(latest)) {
            latest = d.reviewedAt;
          }
        }
      }
      if (latest != null) {
        rejectedAt ??= latest;
        resubmitAfter ??= latest.add(const Duration(days: 30));
        final remaining =
            resubmitAfter.difference(DateTime.now()).inDays + 1;
        daysRemaining ??= remaining > 0 ? remaining : 0;
        canResubmit = DateTime.now().isAfter(resubmitAfter) ||
            DateTime.now().isAtSameMomentAs(resubmitAfter);
        if (json['can_resubmit'] is bool) {
          canResubmit = json['can_resubmit'] as bool;
        }
      }
    }

    return AccountUpgradeStatusModel(
      lenderId: json['lender_id'] ?? '',
      accountUpgradeStatus: json['account_upgrade_status'] ?? 'not_submitted',
      documents: docs,
      rejectedAt: rejectedAt,
      resubmitAfter: resubmitAfter,
      daysRemaining: daysRemaining,
      canResubmit: canResubmit,
    );
  }

  bool get isNotEmpty => documents.isNotEmpty;
  bool get isEmpty => documents.isEmpty;
  AccountUpgradeDocumentModel get first => documents.first;
  bool get isRejected => accountUpgradeStatus == 'rejected';
  bool get isInCooldown =>
      isRejected && !canResubmit && resubmitAfter != null;
}
