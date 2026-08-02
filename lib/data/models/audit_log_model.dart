// lib/data/models/audit_log_model.dart
class AuditLogModel {
  final String id;
  final String action;
  final String? performedBy;
  final String? tableName;
  final String? recordId;
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final String? ipAddress;
  final DateTime createdAt;
  final Map<String, dynamic>? performedByUser;

  const AuditLogModel({
    required this.id,
    required this.action,
    this.performedBy,
    this.tableName,
    this.recordId,
    this.oldValues,
    this.newValues,
    this.ipAddress,
    required this.createdAt,
    this.performedByUser,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) => AuditLogModel(
    id: json['id'] ?? '',
    action: json['action'] ?? '',
    performedBy: json['performed_by'],
    tableName: json['table_name'],
    recordId: json['record_id'],
    oldValues: json['old_values'] as Map<String, dynamic>?,
    newValues: json['new_values'] as Map<String, dynamic>?,
    ipAddress: json['ip_address'],
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'])
        : DateTime.now(),
    performedByUser: json['performed_by_user'] as Map<String, dynamic>?,
  );

  String get performedByName {
    if (performedByUser == null) return 'System';
    return '${performedByUser!['first_name'] ?? ''} ${performedByUser!['last_name'] ?? ''}'
        .trim();
  }

  String get actionLabel => action.replaceAll('_', ' ').toUpperCase();
}
