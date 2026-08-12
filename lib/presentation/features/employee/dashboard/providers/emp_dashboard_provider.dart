// lib/presentation/features/employee/dashboard/providers/emp_dashboard_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/kpi_remote_datasource.dart';
import '../../../../../data/models/kpi_employee_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class EmpDashboardState {
  final KpiEmployeeModel kpi;
  final bool isLoading;
  final String? error;

  const EmpDashboardState({
    required this.kpi,
    this.isLoading = false,
    this.error,
  });

  EmpDashboardState copyWith({
    KpiEmployeeModel? kpi,
    bool? isLoading,
    String? error,
  }) =>
      EmpDashboardState(
        kpi: kpi ?? this.kpi,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class EmpDashboardNotifier extends StateNotifier<EmpDashboardState>
    with RealtimeRefreshMixin {
  final KpiRemoteDataSource _ds;

  EmpDashboardNotifier(this._ds)
      : super(EmpDashboardState(kpi: KpiEmployeeModel.empty())) {
    bindRealtimeRefresh([
      'loans',
      'loan_schedules',
      'payments',
      'collection_assignments',
      'credit_investigations',
      'account_upgrade_documents',
      'notifications',
    ], refresh: loadKpis);
    loadKpis();
  }

  Future<void> loadKpis() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final kpi = await _ds.getEmployeeKpis();
      state = state.copyWith(kpi: kpi, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() => loadKpis();
}

final empDashboardProvider =
    AutoDisposeStateNotifierProvider<EmpDashboardNotifier, EmpDashboardState>((ref) {
  return EmpDashboardNotifier(sl<KpiRemoteDataSource>());
});
