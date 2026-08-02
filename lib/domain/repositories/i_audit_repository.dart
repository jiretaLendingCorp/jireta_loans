// lib/domain/repositories/i_audit_repository.dart
abstract class IAuditRepository {
  Future<Map<String, dynamic>> getAuditLogs(
      {String? action, String? performedBy, String? tableName, int page});
}
