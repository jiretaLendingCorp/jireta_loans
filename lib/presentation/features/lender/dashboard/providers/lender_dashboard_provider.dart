// lib/presentation/features/lender/dashboard/providers/lender_dashboard_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/kpi_remote_datasource.dart';
import '../../../../../data/models/kpi_lender_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class LenderDashboardState {
  final KpiLenderModel kpi;
  final bool isLoading;
  final String? error;

  const LenderDashboardState({
    required this.kpi,
    this.isLoading = false,
    this.error,
  });

  LenderDashboardState copyWith({
    KpiLenderModel? kpi,
    bool? isLoading,
    String? error,
  }) =>
      LenderDashboardState(
        kpi: kpi ?? this.kpi,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class LenderDashboardNotifier extends StateNotifier<LenderDashboardState>
    with RealtimeRefreshMixin {
  final KpiRemoteDataSource _ds;

  LenderDashboardNotifier(this._ds)
      : super(const LenderDashboardState(kpi: KpiLenderModel())) {
    bindRealtimeRefresh(
        ['loans', 'loan_schedules', 'payments', 'account_upgrade_documents'],
        refresh: load);
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final kpi = await _ds.getLenderKpis();
      state = state.copyWith(kpi: kpi, isLoading: false);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  Future<void> refresh() => load();
}

final lenderDashboardProvider = AutoDisposeStateNotifierProvider<
    LenderDashboardNotifier, LenderDashboardState>((ref) {
  return LenderDashboardNotifier(sl<KpiRemoteDataSource>());
});
