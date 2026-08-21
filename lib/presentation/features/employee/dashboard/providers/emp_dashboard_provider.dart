// lib/presentation/features/employee/dashboard/providers/emp_dashboard_provider.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
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
  Timer? _pollTimer;

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
    ], refresh: () => loadKpis(silent: true));
    loadKpis();
    // Safety net for the realtime push: browsers throttle background tabs and
    // websockets can silently drop, so poll quietly as well. Missed events
    // self-heal within 30s and the KPI cards stay live either way.
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      loadKpis(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> loadKpis({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final kpi = await _ds.getEmployeeKpis();
      state = state.copyWith(kpi: kpi, isLoading: false);
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  Future<void> refresh() => loadKpis();
}

final empDashboardProvider =
    AutoDisposeStateNotifierProvider<EmpDashboardNotifier, EmpDashboardState>(
        (ref) {
  return EmpDashboardNotifier(sl<KpiRemoteDataSource>());
});
