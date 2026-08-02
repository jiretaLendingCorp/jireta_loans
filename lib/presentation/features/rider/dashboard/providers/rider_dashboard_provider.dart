// lib/presentation/features/rider/dashboard/providers/rider_dashboard_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/kpi_remote_datasource.dart';
import '../../../../../data/datasources/remote/collection_remote_datasource.dart';
import '../../../../../data/datasources/remote/ci_remote_datasource.dart';
import '../../../../../data/models/kpi_rider_model.dart';
import '../../../../../data/models/collection_assignment_model.dart';
import '../../../../../data/models/credit_investigation_model.dart';

class RiderDashboardState {
  final KpiRiderModel kpi;
  final List<CollectionAssignmentModel> todayCollections;
  final List<CreditInvestigationModel> todayCiTasks;
  final bool isLoading;
  final String? error;

  const RiderDashboardState({
    required this.kpi,
    this.todayCollections = const [],
    this.todayCiTasks = const [],
    this.isLoading = false,
    this.error,
  });

  RiderDashboardState copyWith({
    KpiRiderModel? kpi,
    List<CollectionAssignmentModel>? todayCollections,
    List<CreditInvestigationModel>? todayCiTasks,
    bool? isLoading,
    String? error,
  }) =>
      RiderDashboardState(
        kpi: kpi ?? this.kpi,
        todayCollections: todayCollections ?? this.todayCollections,
        todayCiTasks: todayCiTasks ?? this.todayCiTasks,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

class RiderDashboardNotifier extends StateNotifier<RiderDashboardState> {
  final KpiRemoteDataSource _kpiDs;
  final CollectionRemoteDataSource _collDs;
  final CiRemoteDataSource _ciDs;

  RiderDashboardNotifier(this._kpiDs, this._collDs, this._ciDs)
      : super(RiderDashboardState(kpi: KpiRiderModel.empty())) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final results = await Future.wait([
        _kpiDs.getRiderKpis(),
        _collDs.getCollectionList(status: 'accepted', page: 1),
        _ciDs.getCiList(status: 'accepted', page: 1),
      ]);
      state = state.copyWith(
        kpi: results[0] as KpiRiderModel,
        todayCollections: results[1] as List<CollectionAssignmentModel>,
        todayCiTasks: results[2] as List<CreditInvestigationModel>,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() => load();
}

final riderDashboardProvider =
    StateNotifierProvider<RiderDashboardNotifier, RiderDashboardState>((ref) {
  return RiderDashboardNotifier(
    sl<KpiRemoteDataSource>(),
    sl<CollectionRemoteDataSource>(),
    sl<CiRemoteDataSource>(),
  );
});
