// lib/presentation/features/rider/history/providers/rider_history_provider.dart
// Rider History — pinagsamang history ng lahat ng natapos na gawain:
// completed collections, completed CI investigations, at completed cash
// deliveries. May buwanang (month) filter na server-side (date range).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../data/datasources/remote/ci_remote_datasource.dart';
import '../../../../../data/datasources/remote/collection_remote_datasource.dart';
import '../../../../../data/datasources/remote/disbursement_remote_datasource.dart';
import '../../../../../data/models/collection_assignment_model.dart';
import '../../../../../data/models/credit_investigation_model.dart';
import '../../../../../data/models/disbursement_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class RiderHistoryState {
  final List<CollectionAssignmentModel> collections;
  final List<CreditInvestigationModel> ciTasks;
  final List<DisbursementModel> deliveries;
  final bool isLoading;
  final String? error;

  /// `YYYY-MM` o null para sa all-time.
  final String? selectedMonth;

  const RiderHistoryState({
    this.collections = const [],
    this.ciTasks = const [],
    this.deliveries = const [],
    this.isLoading = false,
    this.error,
    this.selectedMonth,
  });

  RiderHistoryState copyWith({
    List<CollectionAssignmentModel>? collections,
    List<CreditInvestigationModel>? ciTasks,
    List<DisbursementModel>? deliveries,
    bool? isLoading,
    String? error,
    String? selectedMonth,
  }) =>
      RiderHistoryState(
        collections: collections ?? this.collections,
        ciTasks: ciTasks ?? this.ciTasks,
        deliveries: deliveries ?? this.deliveries,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        selectedMonth: selectedMonth ?? this.selectedMonth,
      );

  int get total => collections.length + ciTasks.length + deliveries.length;
}

class RiderHistoryNotifier extends StateNotifier<RiderHistoryState>
    with RealtimeRefreshMixin {
  final CollectionRemoteDataSource _collDs;
  final CiRemoteDataSource _ciDs;
  final DisbursementRemoteDataSource _disbDs;

  RiderHistoryNotifier(this._collDs, this._ciDs, this._disbDs)
      : super(const RiderHistoryState()) {
    bindRealtimeRefresh(
      ['collection_assignments', 'credit_investigations', 'disbursements'],
      refresh: () => load(silent: true),
    );
    load();
  }

  /// 12 buwan pabalik (kasama ang kasalukuyan) — pareho sa rider dashboard.
  static List<String> availableMonths({int count = 12}) {
    final now = DateTime.now();
    return List.generate(count, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });
  }

  /// `YYYY-MM` -> `Sep 2026`.
  static String monthLabel(String yyyyMm) {
    const mNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final parts = yyyyMm.split('-');
    if (parts.length != 2) return yyyyMm;
    final m = int.tryParse(parts[1]) ?? 1;
    if (m < 1 || m > 12) return yyyyMm;
    return '${mNames[m - 1]} ${parts[0]}';
  }

  /// (date_from, date_to) para sa buwan, o null kapag all-time.
  static (String, String)? _monthRange(String? month) {
    if (month == null || month.isEmpty) return null;
    final parts = month.split('-');
    if (parts.length != 2) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y == null || m == null || m < 1 || m > 12) return null;
    final from = DateTime(y, m, 1);
    final to = DateTime(y, m + 1, 0); // huling araw ng buwan
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return (fmt(from), fmt(to));
  }

  static DateTime _collectionDate(CollectionAssignmentModel c) =>
      c.completedAt ?? c.collectionSchedule ?? c.createdAt;

  static DateTime _ciDate(CreditInvestigationModel ci) =>
      ci.completedAt ?? ci.reviewedAt ?? ci.createdAt;

  static DateTime _deliveryDate(DisbursementModel d) =>
      d.disbursedAt ?? d.deliveryDate ?? d.createdAt;

  Future<void> load({bool silent = false, String? month}) async {
    final m = month ?? state.selectedMonth;
    final range = _monthRange(m);
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      // Parallel — tatlong table ang kailangan.
      final collFuture = _collDs.getCollectionList(
        status: 'completed',
        dateFrom: range?.$1,
        dateTo: range?.$2,
        page: 1,
        limit: 50,
      );
      // Kasama ang approved/rejected: pag na-review ng staff ang CI,
      // lumalabas ito sa `completed` at "nawawala" sana sa history.
      final ciFuture = _ciDs.getCiList(
        status: 'completed,approved,rejected',
        startDate: range?.$1,
        endDate: range?.$2,
        page: 1,
        limit: 50,
      );
      final disbFuture = _disbDs.getDisbursementList(
        method: 'rider_delivery',
        status: 'completed',
        dateFrom: range?.$1,
        dateTo: range?.$2,
        page: 1,
        limit: 50,
      );

      final collections = (await collFuture)
        ..sort((a, b) => _collectionDate(b).compareTo(_collectionDate(a)));
      final ciTasks = (await ciFuture)
        ..sort((a, b) => _ciDate(b).compareTo(_ciDate(a)));
      final deliveries = (await disbFuture)
        ..sort((a, b) => _deliveryDate(b).compareTo(_deliveryDate(a)));

      state = state.copyWith(
        collections: collections,
        ciTasks: ciTasks,
        deliveries: deliveries,
        isLoading: false,
        selectedMonth: m,
      );
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  Future<void> setMonth(String? month) => load(month: month);

  Future<void> clearFilter() => load(month: null);

  Future<void> refresh() => load();
}

final riderHistoryProvider =
    AutoDisposeStateNotifierProvider<RiderHistoryNotifier, RiderHistoryState>(
        (ref) {
  return RiderHistoryNotifier(
    sl<CollectionRemoteDataSource>(),
    sl<CiRemoteDataSource>(),
    sl<DisbursementRemoteDataSource>(),
  );
});
