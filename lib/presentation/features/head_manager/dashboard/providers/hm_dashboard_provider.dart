// lib/presentation/features/head_manager/dashboard/providers/hm_dashboard_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/kpi_remote_datasource.dart';
import '../../../../../data/models/kpi_head_manager_model.dart';

class HmDashboardState {
  final KpiHeadManagerModel kpi;
  final bool isLoading;
  final String? error;

  const HmDashboardState({
    required this.kpi,
    this.isLoading = false,
    this.error,
  });

  HmDashboardState copyWith({
    KpiHeadManagerModel? kpi,
    bool? isLoading,
    String? error,
  }) => HmDashboardState(
    kpi: kpi ?? this.kpi,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );
}

class HmDashboardNotifier extends StateNotifier<HmDashboardState> {
  final KpiRemoteDataSource _ds;

  HmDashboardNotifier(this._ds)
    : super(HmDashboardState(kpi: KpiHeadManagerModel.empty())) {
    loadKpis();
  }

  Future<void> loadKpis() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final kpi = await _ds.getHeadManagerKpis();
      state = state.copyWith(kpi: kpi, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() => loadKpis();
}

final hmDashboardProvider =
    StateNotifierProvider<HmDashboardNotifier, HmDashboardState>((ref) {
      return HmDashboardNotifier(sl<KpiRemoteDataSource>());
    });
