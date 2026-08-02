// lib/presentation/features/head_manager/audit/providers/hm_audit_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/audit_remote_datasource.dart';

final hmAuditProvider =
    StateNotifierProvider<HmAuditNotifier, AsyncValue<Map<String, dynamic>>>(
        (ref) {
  return HmAuditNotifier(sl<AuditRemoteDataSource>());
});

class HmAuditNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final AuditRemoteDataSource _ds;
  HmAuditNotifier(this._ds) : super(const AsyncData({'items': [], 'total': 0}));

  Future<void> loadLogs(
      {String? action,
      String? performedBy,
      String? tableName,
      int page = 1}) async {
    state = const AsyncLoading();
    try {
      final data = await _ds.getLogs(
          action: action,
          performedBy: performedBy,
          tableName: tableName,
          page: page);
      state = AsyncData(data);
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }
}
