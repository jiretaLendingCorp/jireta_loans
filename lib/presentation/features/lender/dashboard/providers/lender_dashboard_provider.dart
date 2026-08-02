// lib/presentation/features/lender/dashboard/providers/lender_dashboard_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/kpi_remote_datasource.dart';
import '../../../../../data/models/kpi_lender_model.dart';

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

class LenderDashboardNotifier extends StateNotifier<LenderDashboardState> {
  final KpiRemoteDataSource _ds;

  LenderDashboardNotifier(this._ds)
      : super(const LenderDashboardState(kpi: KpiLenderModel())) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final kpi = await _ds.getLenderKpis();
      state = state.copyWith(kpi: kpi, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() => load();
}

final lenderDashboardProvider =
    StateNotifierProvider<LenderDashboardNotifier, LenderDashboardState>((ref) {
  return LenderDashboardNotifier(sl<KpiRemoteDataSource>());
});
