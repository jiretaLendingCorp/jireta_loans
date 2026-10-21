// lib/presentation/features/head_manager/rider_quotas/providers/hm_rider_quotas_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/di/injection.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../data/datasources/remote/collection_remote_datasource.dart';
import '../../../../../data/models/rider_quota_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmRiderQuotasState {
  final RiderQuotaSummary summary;
  final List<RiderQuota> rows;
  final bool isLoading;
  final String? error;
  final int page;
  final int totalPages;
  final int total;
  final String search;
  final String period;
  final String statusFilter;
  final String? dateFrom;
  final String? dateTo;
  final String sortKey;
  final String sortDir;

  /// Nakabinbin na save/close — hindi na doble-doble ang submit.
  final bool isSaving;

  /// Error mula sa create/update/close (ipinapakita sa modal, hindi sa table).
  final String? actionError;

  const HmRiderQuotasState({
    this.summary = const RiderQuotaSummary(),
    this.rows = const [],
    this.isLoading = false,
    this.error,
    this.page = 1,
    this.totalPages = 1,
    this.total = 0,
    this.search = '',
    this.period = '',
    this.statusFilter = 'all',
    this.dateFrom,
    this.dateTo,
    this.sortKey = 'start_date',
    this.sortDir = 'desc',
    this.isSaving = false,
    this.actionError,
  });

  HmRiderQuotasState copyWith({
    RiderQuotaSummary? summary,
    List<RiderQuota>? rows,
    bool? isLoading,
    String? error,
    int? page,
    int? totalPages,
    int? total,
    String? search,
    String? period,
    String? statusFilter,
    String? dateFrom,
    String? dateTo,
    String? sortKey,
    String? sortDir,
    bool? isSaving,
    String? actionError,
  }) =>
      HmRiderQuotasState(
        summary: summary ?? this.summary,
        rows: rows ?? this.rows,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        page: page ?? this.page,
        totalPages: totalPages ?? this.totalPages,
        total: total ?? this.total,
        search: search ?? this.search,
        period: period ?? this.period,
        statusFilter: statusFilter ?? this.statusFilter,
        dateFrom: dateFrom ?? this.dateFrom,
        dateTo: dateTo ?? this.dateTo,
        sortKey: sortKey ?? this.sortKey,
        sortDir: sortDir ?? this.sortDir,
        isSaving: isSaving ?? this.isSaving,
        actionError: actionError ?? this.actionError,
      );
}

/// Server-side ang aggregation, status derivation at pagination — ang UI ay
/// hindi nagko-compute ng confirmed/remaining. Isang RPC (00187) ang
/// pinagmumulan para pareho ang totals sa quota page, rider app at audit.
class HmRiderQuotasNotifier extends StateNotifier<HmRiderQuotasState>
    with RealtimeRefreshMixin {
  final CollectionRemoteDataSource _ds;

  /// Iniiwasan ang out-of-order response (mabagal na lumang filter na
  /// naka-overwrite sa bago).
  int _requestSeq = 0;

  HmRiderQuotasNotifier(this._ds) : super(const HmRiderQuotasState()) {
    bindRealtimeRefresh(
      ['rider_quotas', 'payments', 'collection_assignments'],
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
      final result = await _ds.getRiderQuotas(
        period: state.period,
        status: state.statusFilter,
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
        search: state.search,
        sort: state.sortKey,
        dir: state.sortDir,
        page: page,
        limit: 20,
      );
      if (!mounted || seq != _requestSeq) return;
      // Naubos ang huling page (hal. na-close ang quota) — bumalik sa huling
      // page na may laman imbes na blangkong table.
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

  void setPeriod(String value) {
    state = state.copyWith(period: value, page: 1);
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

  /// `value` ay `key:dir` (hal. `completion_percentage:desc`).
  void setSort(String value) {
    final parts = value.split(':');
    final key = parts.isNotEmpty ? parts[0] : 'start_date';
    final dir = parts.length > 1 ? parts[1] : 'desc';
    state = state.copyWith(sortKey: key, sortDir: dir, page: 1);
    load(silent: true);
  }

  void setPage(int page) => load(page: page, silent: true);

  Future<void> refresh() => load(silent: true);

  /// `true` kapag na-save; ang error ay nasa `state.actionError`.
  Future<bool> createQuota({
    required String riderId,
    required String period,
    required double targetAmount,
    required String startDate,
    required String endDate,
    String? notes,
  }) async {
    if (state.isSaving) return false;
    state = state.copyWith(isSaving: true, actionError: null);
    try {
      await _ds.createRiderQuota(
        riderId: riderId,
        period: period,
        targetAmount: targetAmount,
        startDate: startDate,
        endDate: endDate,
        notes: notes,
      );
      state = state.copyWith(isSaving: false, actionError: null);
      await load(silent: true);
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        isSaving: false,
        actionError: ErrorHandler.handle(e).message,
      );
      return false;
    }
  }

  Future<bool> updateQuota({
    required String quotaId,
    required String period,
    required double targetAmount,
    required String startDate,
    required String endDate,
    String? notes,
  }) async {
    if (state.isSaving) return false;
    state = state.copyWith(isSaving: true, actionError: null);
    try {
      await _ds.updateRiderQuota(
        quotaId: quotaId,
        period: period,
        targetAmount: targetAmount,
        startDate: startDate,
        endDate: endDate,
        notes: notes,
      );
      state = state.copyWith(isSaving: false, actionError: null);
      await load(silent: true);
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        isSaving: false,
        actionError: ErrorHandler.handle(e).message,
      );
      return false;
    }
  }

  Future<bool> closeQuota(String quotaId) async {
    if (state.isSaving) return false;
    state = state.copyWith(isSaving: true, actionError: null);
    try {
      await _ds.closeRiderQuota(quotaId);
      state = state.copyWith(isSaving: false, actionError: null);
      await load(silent: true);
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        isSaving: false,
        actionError: ErrorHandler.handle(e).message,
      );
      return false;
    }
  }

  void clearActionError() => state = state.copyWith(actionError: null);
}

final hmRiderQuotasProvider = AutoDisposeStateNotifierProvider<
    HmRiderQuotasNotifier, HmRiderQuotasState>(
  (ref) => HmRiderQuotasNotifier(sl<CollectionRemoteDataSource>()),
);

/// Active riders para sa assign form. Auto-dispose: sariwa lagi sa bawat
/// pagbukas ng modal (may bagong rider o na-archive).
final riderQuotaRiderOptionsProvider =
    AutoDisposeFutureProvider<List<RiderQuotaRiderOption>>((ref) async {
  return sl<CollectionRemoteDataSource>().getRiderQuotaRiders();
});
