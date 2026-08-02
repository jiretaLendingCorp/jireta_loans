// lib/domain/entities/audit_log_entity.dart
class AuditLogEntity {
  final String id;
  final String performedById;
  final String? performedByName;
  final String? performedByRole;
  final String action;
  final String? tableName;
  final String? recordId;
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final String? ipAddress;
  final String? userAgent;
  final DateTime createdAt;

  const AuditLogEntity({
    required this.id,
    required this.performedById,
    this.performedByName,
    this.performedByRole,
    required this.action,
    this.tableName,
    this.recordId,
    this.oldValues,
    this.newValues,
    this.ipAddress,
    this.userAgent,
    required this.createdAt,
  });
}
