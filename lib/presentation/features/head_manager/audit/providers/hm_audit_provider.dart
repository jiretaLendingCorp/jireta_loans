// lib/presentation/features/head_manager/audit/providers/hm_audit_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/audit_remote_datasource.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

final hmAuditProvider =
    AutoDisposeStateNotifierProvider<HmAuditNotifier, AsyncValue<Map<String, dynamic>>>(
        (ref) {
  return HmAuditNotifier(sl<AuditRemoteDataSource>());
});

class HmAuditNotifier extends StateNotifier<AsyncValue<Map<String, dynamic>>>
    with RealtimeRefreshMixin {
  final AuditRemoteDataSource _ds;
  HmAuditNotifier(this._ds) : super(const AsyncData({'items': [], 'total': 0})) {
    bindRealtimeRefresh(['audit_logs'], refresh: loadLogs);
  }

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
