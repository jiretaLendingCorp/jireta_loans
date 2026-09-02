// lib/presentation/features/head_manager/dashboard/providers/hm_dashboard_provider.dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/utils/timezone.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/kpi_remote_datasource.dart';
import '../../../../../data/models/kpi_head_manager_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmDashboardState {
  final KpiHeadManagerModel kpi;
  final bool isLoading;
  final String? error;
  final String selectedMonth; // YYYY-MM

  HmDashboardState({
    required this.kpi,
    this.isLoading = false,
    this.error,
    String? selectedMonth,
  }) : selectedMonth = selectedMonth ?? _currentMonth();

  static String _currentMonth() {
    final now = nowManila();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  HmDashboardState copyWith({
    KpiHeadManagerModel? kpi,
    bool? isLoading,
    String? error,
    String? selectedMonth,
  }) =>
      HmDashboardState(
        kpi: kpi ?? this.kpi,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        selectedMonth: selectedMonth ?? this.selectedMonth,
      );
}

class HmDashboardNotifier extends StateNotifier<HmDashboardState>
    with RealtimeRefreshMixin {
  final KpiRemoteDataSource _ds;
  Timer? _pollTimer;
  int _loadSeq = 0;

  HmDashboardNotifier(this._ds)
      : super(HmDashboardState(kpi: KpiHeadManagerModel.empty())) {
    bindRealtimeRefresh([
      'loans',
      'loan_schedules',
      'payments',
      'penalty_logs',
      'collection_assignments',
      'credit_investigations',
      'account_upgrade_documents',
      'lender_profiles',
      'in_office_applications',
      'disbursements',
      'reports',
      'users',
      'notifications',
    ], refresh: () => loadKpis(silent: true));
    loadKpis();
    // Safety net for the realtime push: browsers throttle background tabs and
    // websockets can silently drop, so poll quietly as well. Missed events
    // self-heal within 30s and the analytics charts stay live either way.
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      loadKpis(silent: true);
    });
  }

  /// Month helpers — generates last 12 months for picker (newest first)
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
      // Head manager dashboard is MONTHLY: always pass selectedMonth
      final kpi = await _ds.getHeadManagerKpis(month: m);
      // Stale guard: if a newer request started after this one, discard result
      // This prevents the initial load for the current month from overwriting
      // a user-selected month when the user switches months quickly.
      if (seq != _loadSeq) return;
      // Also discard if selectedMonth was changed externally to a different month
      // while this request was in flight — the KPI belongs to the old month.
      if (state.selectedMonth != m && month != null) {
        // If caller explicitly asked for m, but state is now different, still
        // apply only if nothing newer is pending (seq check above passed).
        // For explicit month loads we honour the requested month to avoid
        // the "always snaps back to current month" bug; silent refreshes that
        // happen concurrently are discarded above via seq guard.
      }
      state = state.copyWith(kpi: kpi, isLoading: false, selectedMonth: m);
    } catch (e) {
      if (seq != _loadSeq) return;
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
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

final hmDashboardProvider =
    AutoDisposeStateNotifierProvider<HmDashboardNotifier, HmDashboardState>(
        (ref) {
  return HmDashboardNotifier(sl<KpiRemoteDataSource>());
});
