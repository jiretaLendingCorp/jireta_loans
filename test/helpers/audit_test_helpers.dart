import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:jireta_loans/core/network/dio_client.dart';
import 'package:jireta_loans/data/datasources/remote/audit_remote_datasource.dart';

/// Loads the real .env from the repo so [DioClient] (and the datasources that
/// depend on it) can be constructed inside tests. `flutter test` runs with the
/// package root as the working directory, so the relative path resolves.
Future<void> loadTestEnv() async {
  if (dotenv.isInitialized) return;
  final content = await File('assets/env/.env').readAsString();
  dotenv.testLoad(fileInput: content);
}

/// [DioClient] whose `get` returns canned responses without any network I/O.
class FakeDioClient extends DioClient {
  FakeDioClient(this.handler) : super();
  final Future<Response<dynamic>> Function(RequestOptions options) handler;

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParams,
  }) async {
    return handler(
      RequestOptions(path: path, queryParameters: queryParams ?? const {}),
    );
  }
}

/// Convenience: builds a fake audit datasource backed by [handler].
AuditRemoteDataSource fakeAuditDataSource(
  Future<Response<dynamic>> Function(RequestOptions options) handler) {
  return AuditRemoteDataSource(FakeDioClient(handler));
}

/// A canned backend response for `audit-get-logs` (matches the Edge Function's
/// `{ data, meta: { page, limit, total, total_pages } }` envelope).
Map<String, dynamic> auditResponse({
  List<Map<String, dynamic>> logs = const [],
  int page = 1,
  int limit = 20,
}) {
  return {
    'data': logs,
    'meta': {
      'page': page,
      'limit': limit,
      'total': logs.length,
      'total_pages': logs.isEmpty ? 1 : (logs.length / limit).ceil(),
    },
  };
}

Map<String, dynamic> auditLogRow({
  String id = '11111111-1111-1111-1111-111111111111',
  String action = 'loan_applied',
  String? tableName = 'loans',
  Map<String, dynamic>? oldValues,
  Map<String, dynamic>? newValues,
  Map<String, dynamic>? performedByUser,
}) {
  return {
    'id': id,
    'action': action,
    'table_name': tableName,
    'record_id': '22222222-2222-2222-2222-222222222222',
    'old_values': oldValues,
    'new_values': newValues,
    'ip_address': '127.0.0.1',
    'created_at': '2026-08-01T10:30:00.000Z',
    'performed_by_user': performedByUser,
  };
}
