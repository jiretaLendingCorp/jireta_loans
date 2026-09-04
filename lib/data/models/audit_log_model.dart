// lib/data/models/audit_log_model.dart
import '../../core/utils/timezone.dart';

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
            ? parseManila(json['created_at'])!
            : DateTime.now(),
        performedByUser: json['performed_by_user'] as Map<String, dynamic>?,
      );

  String get performedByName {
    if (performedByUser == null) {
      return 'System';
    }
    final f = (performedByUser!['first_name'] as String? ?? '').trim();
    final l = (performedByUser!['last_name'] as String? ?? '').trim();
    final full = '$f $l'.trim();
    if (full.isNotEmpty) {
      return full;
    }
    final email = (performedByUser!['email'] as String? ?? '').trim();
    if (email.isNotEmpty) {
      return email;
    }
    final phone = (performedByUser!['phone_number'] as String? ?? '').trim();
    if (phone.isNotEmpty) {
      return phone;
    }
    final roles = performedByUser!['roles'];
    String? roleName;
    if (roles is Map) {
      roleName = roles['name'] as String?;
    }
    if (roleName != null && roleName.isNotEmpty) {
      return roleName
          .split('_')
          .where((w) => w.isNotEmpty)
          .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
    }
    if (performedBy != null && performedBy!.isNotEmpty) {
      return 'User ${performedBy!.substring(0, 8)}';
    }
    return 'Unknown';
  }

  String get performerInitials {
    if (performedByUser == null) {
      return 'S';
    }
    final f = (performedByUser!['first_name'] as String? ?? '').trim();
    final l = (performedByUser!['last_name'] as String? ?? '').trim();
    final initials = '${f.isNotEmpty ? f[0] : ''}${l.isNotEmpty ? l[0] : ''}';
    if (initials.isNotEmpty) {
      return initials.toUpperCase();
    }
    final email = (performedByUser!['email'] as String? ?? '').trim();
    if (email.isNotEmpty) {
      return email[0].toUpperCase();
    }
    final phone = (performedByUser!['phone_number'] as String? ?? '').trim();
    if (phone.isNotEmpty) {
      return phone[0].toUpperCase();
    }
    final roles = performedByUser!['roles'];
    String? roleName;
    if (roles is Map) {
      roleName = roles['name'] as String?;
    }
    if (roleName != null && roleName.isNotEmpty) {
      return roleName[0].toUpperCase();
    }
    return 'U';
  }

  String get actionLabel => action.replaceAll('_', ' ').toUpperCase();
}
