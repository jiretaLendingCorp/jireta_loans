// lib/data/repositories/audit_repository_impl.dart
import '../../domain/repositories/i_audit_repository.dart';
import '../datasources/remote/audit_remote_datasource.dart';

class AuditRepositoryImpl implements IAuditRepository {
  final AuditRemoteDataSource _ds;
  AuditRepositoryImpl(this._ds);

  @override
  Future<Map<String, dynamic>> getAuditLogs({
    String? action,
    String? performedBy,
    String? tableName,
    int page = 1,
  }) =>
      _ds.getAuditLogs(
          action: action,
          performedBy: performedBy,
          tableName: tableName,
          page: page);
}
