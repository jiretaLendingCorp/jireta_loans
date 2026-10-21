// lib/presentation/features/head_manager/rider_monitoring/providers/hm_rider_monitoring_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../data/datasources/remote/collection_remote_datasource.dart';
import '../../../../../data/models/rider_collection_monitoring_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmRiderMonitoringState {
  final RiderMonitoringSummary summary;
  final List<RiderMonitoringRow> rows;
  final bool isLoading;
  final String? error;
  final int page;
  final int totalPages;
  final int total;
  final String search;
  final String statusFilter;

  /// `YYYY-MM-DD` (Manila) — due date ng installment at petsa ng verified
  /// payment sa server. Null = buong history.
  final String? dateFrom;
  final String? dateTo;
  final String sortKey;
  final String sortDir;

  const HmRiderMonitoringState({
    this.summary = const RiderMonitoringSummary(),
    this.rows = const [],
    this.isLoading = false,
    this.error,
    this.page = 1,
    this.totalPages = 1,
    this.total = 0,
    this.search = '',
    this.statusFilter = 'all',
    this.dateFrom,
    this.dateTo,
    this.sortKey = 'rider_name',
    this.sortDir = 'asc',
  });

  HmRiderMonitoringState copyWith({
    RiderMonitoringSummary? summary,
    List<RiderMonitoringRow>? rows,
    bool? isLoading,
    String? error,
    int? page,
    int? totalPages,
    int? total,
    String? search,
    String? statusFilter,
    String? dateFrom,
    String? dateTo,
    String? sortKey,
    String? sortDir,
  }) =>
      HmRiderMonitoringState(
        summary: summary ?? this.summary,
        rows: rows ?? this.rows,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        page: page ?? this.page,
        totalPages: totalPages ?? this.totalPages,
        total: total ?? this.total,
        search: search ?? this.search,
        statusFilter: statusFilter ?? this.statusFilter,
        dateFrom: dateFrom ?? this.dateFrom,
        dateTo: dateTo ?? this.dateTo,
        sortKey: sortKey ?? this.sortKey,
        sortDir: sortDir ?? this.sortDir,
      );
}

/// Server-side ang aggregation, sorting at pagination. Ang UI ay hindi
/// nagko-compute ng confirmed/remaining — galing lahat sa RPC (00186) para
/// siguradong pareho ang totals sa reports at sa MySQL/DB records.
class HmRiderMonitoringNotifier extends StateNotifier<HmRiderMonitoringState>
    with RealtimeRefreshMixin {
  final CollectionRemoteDataSource _ds;

  /// Iniiwasan ang out-of-order response (mabagal na lumang search na
  /// naka-overwrite sa bagong filter).
  int _requestSeq = 0;

  HmRiderMonitoringNotifier(this._ds) : super(const HmRiderMonitoringState()) {
    bindRealtimeRefresh(
      ['collection_assignments', 'payments'],
      refresh: () => load(silent: true),
    );
    load();
  }

  Future<void> load({int page = 1, bool silent = false}) async {
    final seq = ++_requestSeq;
    if (!silent && state.rows.isEmpty) {
      state = state.copyWith(isLoading: true, error: null);
    }
    try {
      final result = await _ds.getRiderMonitoring(
        status: state.statusFilter,
        search: state.search,
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
        sort: state.sortKey,
        dir: state.sortDir,
        page: page,
        limit: 20,
      );
      if (!mounted || seq != _requestSeq) return;
      // Naubos ang huling page (hal. na-archive ang rider) — bumalik sa
      // huling page na may laman imbes na blangkong table.
      if (result.rows.isEmpty && page > 1) {
        state = state.copyWith(page: page - 1);
        return load(page: page - 1, silent: true);
      }
      state = state.copyWith(
        rows: result.rows,
        summary: result.summary,
        isLoading: false,
        page: result.page,
        totalPages: result.totalPages,
        total: result.total,
      );
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      if (silent) return;
      state = state.copyWith(
        isLoading: false,
        error: ErrorHandler.handle(e).message,
      );
    }
  }

  void setSearch(String value) {
    state = state.copyWith(search: value, page: 1);
    load(silent: true);
  }

  void setStatus(String status) {
    state = state.copyWith(statusFilter: status, page: 1);
    load(silent: true);
  }

  void setDateRange(String? from, String? to) {
    state = state.copyWith(dateFrom: from, dateTo: to, page: 1);
    load(silent: true);
  }

  /// `value` ay `key:dir` (hal. `confirmed_collection:desc`).
  void setSort(String value) {
    final parts = value.split(':');
    final key = parts.isNotEmpty ? parts[0] : 'rider_name';
    final dir = parts.length > 1 ? parts[1] : 'asc';
    state = state.copyWith(sortKey: key, sortDir: dir, page: 1);
    load(silent: true);
  }

  void setPage(int page) => load(page: page, silent: true);

  Future<void> refresh() => load(silent: true);
}

final hmRiderMonitoringProvider = AutoDisposeStateNotifierProvider<
    HmRiderMonitoringNotifier, HmRiderMonitoringState>(
  (ref) => HmRiderMonitoringNotifier(sl<CollectionRemoteDataSource>()),
);

// ── Detail ──────────────────────────────────────────────────────────────────

typedef RiderMonitoringDetailArgs = ({
  String riderId,
  String? dateFrom,
  String? dateTo,
});

class HmRiderMonitoringDetailState {
  final RiderMonitoringDetail? detail;
  final bool isLoading;
  final String? error;

  const HmRiderMonitoringDetailState({
    this.detail,
    this.isLoading = false,
    this.error,
  });
}

class HmRiderMonitoringDetailNotifier
    extends StateNotifier<HmRiderMonitoringDetailState>
    with RealtimeRefreshMixin {
  final CollectionRemoteDataSource _ds;
  final RiderMonitoringDetailArgs args;

  HmRiderMonitoringDetailNotifier(this._ds, this.args)
      : super(const HmRiderMonitoringDetailState()) {
    bindRealtimeRefresh(
      ['collection_assignments', 'payments'],
      refresh: () => load(silent: true),
    );
    load();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      state = HmRiderMonitoringDetailState(
        detail: state.detail,
        isLoading: state.detail == null,
      );
    }
    try {
      final detail = await _ds.getRiderMonitoringDetail(
        args.riderId,
        dateFrom: args.dateFrom,
        dateTo: args.dateTo,
      );
      if (!mounted) return;
      state = HmRiderMonitoringDetailState(detail: detail, isLoading: false);
    } catch (e) {
      if (!mounted || silent) return;
      state = HmRiderMonitoringDetailState(
        detail: state.detail,
        isLoading: false,
        error: ErrorHandler.handle(e).message,
      );
    }
  }
}

final hmRiderMonitoringDetailProvider = AutoDisposeStateNotifierProviderFamily<
    HmRiderMonitoringDetailNotifier,
    HmRiderMonitoringDetailState,
    RiderMonitoringDetailArgs>(
  (ref, args) => HmRiderMonitoringDetailNotifier(
    sl<CollectionRemoteDataSource>(),
    args,
  ),
);
