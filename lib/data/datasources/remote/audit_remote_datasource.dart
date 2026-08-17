// lib/data/datasources/remote/audit_remote_datasource.dart
import '../../../core/network/dio_client.dart';
import '../../../core/network/api_endpoints.dart';

class AuditRemoteDataSource {
  final DioClient _client;
  AuditRemoteDataSource(this._client);

  Future<Map<String, dynamic>> getAuditLogs({
    String? action,
    String? performedBy,
    String? tableName,
    String? startDate,
    String? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _client.get(
      ApiEndpoints.auditGetLogs,
      queryParams: {
        if (action != null) 'action': action,
        if (performedBy != null) 'performed_by': performedBy,
        if (tableName != null) 'table_name': tableName,
        if (startDate != null) 'start_date': startDate,
        if (endDate != null) 'end_date': endDate,
        'page': page,
        'limit': limit,
      },
    );
    final list = (res.data['data'] as List?) ?? [];
    final meta = res.data['meta'] as Map<String, dynamic>? ?? {};
    final total = (res.data['total'] as num?)?.toInt() ??
        (meta['total'] as num?)?.toInt() ??
        list.length;
    final totalPages = (res.data['totalPages'] as num?)?.toInt() ??
        (meta['total_pages'] as num?)?.toInt() ??
        (limit == 0 ? 1 : (total / limit).ceil());
    return {
      'data': list,
      'meta': {'page': page, 'total_pages': totalPages, 'total': total},
    };
  }

  Future<Map<String, dynamic>> getLogs({
    String? action,
    String? performedBy,
    String? tableName,
    int page = 1,
    int limit = 20,
  }) =>
      getAuditLogs(
        action: action,
        performedBy: performedBy,
        tableName: tableName,
        page: page,
        limit: limit,
      );
}
