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

  const RiderDashboardState({
    required this.kpi,
    this.todayCollections = const [],
    this.todayCiTasks = const [],
    this.todayDeliveries = const [],
    this.isLoading = false,
    this.error,
  });

  RiderDashboardState copyWith({
    KpiRiderModel? kpi,
    List<CollectionAssignmentModel>? todayCollections,
    List<CreditInvestigationModel>? todayCiTasks,
    List<DisbursementModel>? todayDeliveries,
    bool? isLoading,
    String? error,
  }) =>
      RiderDashboardState(
        kpi: kpi ?? this.kpi,
        todayCollections: todayCollections ?? this.todayCollections,
        todayCiTasks: todayCiTasks ?? this.todayCiTasks,
        todayDeliveries: todayDeliveries ?? this.todayDeliveries,
        isLoading: isLoading ?? this.isLoading,
        error: error,
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

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final results = await Future.wait([
        _kpiDs.getRiderKpis(),
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
      );
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
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
