// lib/data/models/blacklist_model.dart
class BlacklistModel {
  final String id;
  final String lenderId;
  final String reason;
  final String? addedBy;
  final String? removedBy;
  final DateTime? removedAt;
  final bool isActive;
  final DateTime createdAt;
  final Map<String, dynamic>? lender;
  final Map<String, dynamic>? addedByUser;

  const BlacklistModel({
    required this.id,
    required this.lenderId,
    required this.reason,
    this.addedBy,
    this.removedBy,
    this.removedAt,
    required this.isActive,
    required this.createdAt,
    this.lender,
    this.addedByUser,
  });

  factory BlacklistModel.fromJson(Map<String, dynamic> json) => BlacklistModel(
    id: json['id'] ?? '',
    lenderId: json['lender_id'] ?? '',
    reason: json['reason'] ?? '',
    addedBy: json['added_by'],
    removedBy: json['removed_by'],
    removedAt: json['removed_at'] != null
        ? DateTime.parse(json['removed_at'])
        : null,
    isActive: json['is_active'] ?? true,
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'])
        : DateTime.now(),
    lender: json['lender'] as Map<String, dynamic>?,
    addedByUser: json['added_by_user'] as Map<String, dynamic>?,
  );

  String get lenderName {
    if (lender == null) return '';
    return '${lender!['first_name'] ?? ''} ${lender!['last_name'] ?? ''}'
        .trim();
  }

  String get addedByName {
    if (addedByUser == null) return '';
    return '${addedByUser!['first_name'] ?? ''} ${addedByUser!['last_name'] ?? ''}'
        .trim();
  }
}
