// lib/presentation/features/employee/dashboard/providers/emp_dashboard_provider.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/kpi_remote_datasource.dart';
import '../../../../../data/models/kpi_employee_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class EmpDashboardState {
  final KpiEmployeeModel kpi;
  final bool isLoading;
  final String? error;
  final String selectedMonth; // YYYY-MM

  EmpDashboardState({
    required this.kpi,
    this.isLoading = false,
    this.error,
    String? selectedMonth,
  }) : selectedMonth = selectedMonth ?? _currentMonth();

  static String _currentMonth() {
    final now = nowManila();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  EmpDashboardState copyWith({
    KpiEmployeeModel? kpi,
    bool? isLoading,
    String? error,
    String? selectedMonth,
  }) =>
      EmpDashboardState(
        kpi: kpi ?? this.kpi,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        selectedMonth: selectedMonth ?? this.selectedMonth,
      );
}

class EmpDashboardNotifier extends StateNotifier<EmpDashboardState>
    with RealtimeRefreshMixin {
  final KpiRemoteDataSource _ds;
  Timer? _pollTimer;
  int _loadSeq = 0;

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

  /// Month helpers — generates last 12 months for picker (newest first)
  /// Same as head manager dashboard so both stay in sync.
  static List<String> availableMonths({int count = 12}) {
    final now = DateTime.now();
    return List.generate(count, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });
  }

  static String monthLabel(String yyyyMm) {
    const mNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final parts = yyyyMm.split('-');
    if (parts.length != 2) return yyyyMm;
    final y = parts[0];
    final m = int.tryParse(parts[1]) ?? 1;
    return '${mNames[m - 1]} $y';
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> loadKpis({bool silent = false, String? month}) async {
    final m = month ?? state.selectedMonth;
    final seq = ++_loadSeq;
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      // Employee dashboard is MONTHLY (tulad ng head manager): always pass selectedMonth
      final kpi = await _ds.getEmployeeKpis(month: m);
      if (seq != _loadSeq && state.selectedMonth != m) return;
      state = state.copyWith(kpi: kpi, isLoading: false, selectedMonth: m);
    } catch (e) {
      if (seq != _loadSeq && state.selectedMonth != m) return;
      state = state.copyWith(
          isLoading: false,
          error: silent ? state.error : ErrorHandler.handle(e).message);
    }
  }

  Future<void> setMonth(String month) async {
    // Optimistic update so the dropdown reflects the choice immediately,
    // even before the network responds — prevents perceived "snap back".
    state = state.copyWith(selectedMonth: month);
    await loadKpis(month: month);
  }

  Future<void> refresh() => loadKpis(month: state.selectedMonth);
}

final empDashboardProvider =
    AutoDisposeStateNotifierProvider<EmpDashboardNotifier, EmpDashboardState>(
        (ref) {
  return EmpDashboardNotifier(sl<KpiRemoteDataSource>());
});
