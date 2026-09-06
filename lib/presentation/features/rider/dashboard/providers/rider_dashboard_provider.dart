// lib/presentation/features/rider/dashboard/providers/rider_dashboard_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/kpi_remote_datasource.dart';
import '../../../../../data/datasources/remote/collection_remote_datasource.dart';
import '../../../../../data/datasources/remote/ci_remote_datasource.dart';
import '../../../../../data/datasources/remote/disbursement_remote_datasource.dart';
import '../../../../../data/models/kpi_rider_model.dart';
import '../../../../../data/models/collection_assignment_model.dart';
import '../../../../../data/models/credit_investigation_model.dart';
import '../../../../../data/models/disbursement_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class RiderDashboardState {
  final KpiRiderModel kpi;
  final List<CollectionAssignmentModel> todayCollections;
  final List<CreditInvestigationModel> todayCiTasks;
  final List<DisbursementModel> todayDeliveries;
  final bool isLoading;
  final String? error;
  final String? selectedMonth; // YYYY-MM or null (lifetime)
  final String? selectedDate; // YYYY-MM-DD or null

  const RiderDashboardState({
    required this.kpi,
    this.todayCollections = const [],
    this.todayCiTasks = const [],
    this.todayDeliveries = const [],
    this.isLoading = false,
    this.error,
    this.selectedMonth,
    this.selectedDate,
  });

  static String formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  RiderDashboardState copyWith({
    KpiRiderModel? kpi,
    List<CollectionAssignmentModel>? todayCollections,
    List<CreditInvestigationModel>? todayCiTasks,
    List<DisbursementModel>? todayDeliveries,
    bool? isLoading,
    String? error,
    String? selectedMonth,
    String? selectedDate,
    bool clearMonth = false,
    bool clearDate = false,
  }) =>
      RiderDashboardState(
        kpi: kpi ?? this.kpi,
        todayCollections: todayCollections ?? this.todayCollections,
        todayCiTasks: todayCiTasks ?? this.todayCiTasks,
        todayDeliveries: todayDeliveries ?? this.todayDeliveries,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        selectedMonth: clearMonth ? null : (selectedMonth ?? this.selectedMonth),
        selectedDate: clearDate ? null : (selectedDate ?? this.selectedDate),
      );
}

class RiderDashboardNotifier extends StateNotifier<RiderDashboardState>
    with RealtimeRefreshMixin {
  final KpiRemoteDataSource _kpiDs;
  final CollectionRemoteDataSource _collDs;
  final CiRemoteDataSource _ciDs;
  final DisbursementRemoteDataSource _disbDs;

  RiderDashboardNotifier(this._kpiDs, this._collDs, this._ciDs, this._disbDs)
      : super(RiderDashboardState(kpi: KpiRiderModel.empty())) {
    bindRealtimeRefresh([
      'collection_assignments',
      'credit_investigations',
      'disbursements',
      'payments',
      'notifications',
    ], refresh: () => load(silent: true));
    load();
  }

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

  Future<void> load({bool silent = false, String? month, String? date}) async {
    final m = month ?? state.selectedMonth;
    // Exact-day wins over month.
    final d = date ?? state.selectedDate;
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final results = await Future.wait([
        _kpiDs.getRiderKpis(month: d != null ? null : m, date: d),
        _collDs.getCollectionList(status: 'assigned', page: 1),
        _collDs.getCollectionList(status: 'accepted', page: 1),
        // CI: keep visible until completed (assigned + accepted + in_progress)
        _ciDs.getCiList(status: 'assigned', page: 1, limit: 50),
        _ciDs.getCiList(status: 'accepted', page: 1, limit: 50),
        _ciDs.getCiList(status: 'in_progress', page: 1, limit: 50),
        _disbDs.getDisbursementList(
            method: 'rider_delivery', status: 'pending'),
      ]);
      // Merge assigned/accepted/in_progress and sort by deadline/createdAt desc
      final ciMerged = <CreditInvestigationModel>[
        ...results[3] as List<CreditInvestigationModel>,
        ...results[4] as List<CreditInvestigationModel>,
        ...results[5] as List<CreditInvestigationModel>,
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = state.copyWith(
        kpi: results[0] as KpiRiderModel,
        todayCollections: [
          ...results[1] as List<CollectionAssignmentModel>,
          ...results[2] as List<CollectionAssignmentModel>,
        ],
        todayCiTasks: ciMerged,
        todayDeliveries: results[6] as List<DisbursementModel>,
        isLoading: false,
        selectedMonth: m,
        selectedDate: d,
        clearMonth: m == null,
        clearDate: d == null,
      );
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  Future<void> setMonth(String? month) async {
    if (month == null) {
      state = state.copyWith(clearMonth: true, clearDate: true);
      await load(month: null, date: null);
      return;
    }
    state = state.copyWith(selectedMonth: month, clearDate: true);
    await load(month: month, date: null);
  }

  Future<void> setDate(DateTime? date) async {
    if (date == null) {
      state = state.copyWith(clearDate: true);
      await load(date: null);
      return;
    }
    final formatted = RiderDashboardState.formatDate(date);
    final monthKey = formatted.substring(0, 7);
    state = state.copyWith(selectedDate: formatted, selectedMonth: monthKey);
    await load(month: monthKey, date: formatted);
  }

  Future<void> clearFilters() async {
    state = state.copyWith(clearMonth: true, clearDate: true);
    await load(month: null, date: null);
  }

  Future<void> refresh() => load();
}

final riderDashboardProvider = AutoDisposeStateNotifierProvider<
    RiderDashboardNotifier, RiderDashboardState>((ref) {
  return RiderDashboardNotifier(
    sl<KpiRemoteDataSource>(),
    sl<CollectionRemoteDataSource>(),
    sl<CiRemoteDataSource>(),
    sl<DisbursementRemoteDataSource>(),
  );
});
