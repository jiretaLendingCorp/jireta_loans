// lib/presentation/features/head_manager/reports/providers/hm_report_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/report_remote_datasource.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmReportState {
  final List<Map<String, dynamic>> history;
  final bool isLoading;
  final bool isLoadingHistory;
  final String? error;

  const HmReportState({
    this.history = const [],
    this.isLoading = false,
    this.isLoadingHistory = false,
    this.error,
  });

  HmReportState copyWith({
    List<Map<String, dynamic>>? history,
    bool? isLoading,
    bool? isLoadingHistory,
    String? error,
  }) =>
      HmReportState(
        history: history ?? this.history,
        isLoading: isLoading ?? this.isLoading,
        isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
        error: error,
      );
}

final hmReportProvider =
    AutoDisposeStateNotifierProvider<HmReportNotifier, HmReportState>((ref) {
  return HmReportNotifier(sl<ReportRemoteDataSource>());
});

class HmReportNotifier extends StateNotifier<HmReportState>
    with RealtimeRefreshMixin {
  final ReportRemoteDataSource _ds;
  HmReportNotifier(this._ds) : super(const HmReportState()) {
    bindRealtimeRefresh(['reports'], refresh: () => loadHistory(silent: true));
  }

  Future<void> loadTemplates() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _ds.getList();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  Future<void> loadHistory({int page = 1, bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoadingHistory: true, error: null);
    try {
      final history = await _ds.getRawHistory(page: page, limit: 50);
      state = state.copyWith(history: history, isLoadingHistory: false);
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoadingHistory: false, error: ErrorHandler.handle(e).message);
    }
  }

  Future<bool> generateReport(
      String templateKey, Map<String, dynamic> parameters) async {
    try {
      await _ds.generateReport(
        templateKey: templateKey,
        parameters: parameters,
        format: (parameters['format'] ?? 'pdf').toString(),
      );
      await loadHistory();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> generate(
      {required String templateKey, Map<String, dynamic>? parameters}) {
    return generateReport(templateKey, parameters ?? {});
  }
}
