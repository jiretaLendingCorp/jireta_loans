// lib/presentation/features/head_manager/ci/providers/hm_ci_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/ci_remote_datasource.dart';
import '../../../../../data/models/credit_investigation_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmCiState {
  final List<CreditInvestigationModel> items;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final String statusFilter;
  final String search;
  final String? dateFrom;
  final String? dateTo;

  const HmCiState({
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalPages = 1,
    this.totalCount = 0,
    this.statusFilter = 'all',
    this.search = '',
    this.dateFrom,
    this.dateTo,
  });

  HmCiState copyWith({
    List<CreditInvestigationModel>? items,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    String? statusFilter,
    String? search,
    String? dateFrom,
    String? dateTo,
  }) =>
      HmCiState(
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        totalCount: totalCount ?? this.totalCount,
        statusFilter: statusFilter ?? this.statusFilter,
        search: search ?? this.search,
        dateFrom: dateFrom ?? this.dateFrom,
        dateTo: dateTo ?? this.dateTo,
      );
}

class HmCiNotifier extends StateNotifier<HmCiState> with RealtimeRefreshMixin {
  final CiRemoteDataSource _ds;

  HmCiNotifier(this._ds) : super(const HmCiState()) {
    bindRealtimeRefresh(['credit_investigations', 'ci_documents'],
        refresh: () => fetch(silent: true));
    fetch();
  }

  Future<void> fetch({int page = 1, bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _ds.getList(
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
        page: page,
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
      );
      // Kung na-dispose ang notifier habang naghihintay (hal. isinara na ang
      // assign-rider modal), huwag nang hawakan ang `state` — ito ang dahilan
      // ng "Bad state: Tried to use HmCiNotifier after dispose was called."
      if (!mounted) return;
      final list = (res['data'] as List? ?? [])
          .map((e) =>
              CreditInvestigationModel.fromJson(e as Map<String, dynamic>))
          .toList();
      final meta = res['meta'] as Map<String, dynamic>? ?? {};
      state = state.copyWith(
        items: list,
        isLoading: false,
        currentPage: (meta['page'] as num?)?.toInt() ?? 1,
        totalPages: (meta['total_pages'] as num?)?.toInt() ?? 1,
        totalCount: (meta['total'] as num?)?.toInt() ?? list.length,
      );
    } catch (e) {
      if (!mounted || silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setStatus(String s) {
    state = state.copyWith(statusFilter: s);
    fetch();
  }

  void setSearch(String v) {
    state = state.copyWith(search: v);
    fetch();
  }

  void setDateRange(String? from, String? to) {
    state = state.copyWith(dateFrom: from, dateTo: to);
    fetch();
  }

  Future<bool> assignCi({
    required String loanId,
    required String riderId,
    required String notes,
    required String deadline,
  }) async {
    // Kunin ang page BAGO mag-await — kapag na-dispose na ang notifier (hal.
    // isinara ng user ang modal habang nagse-save), hindi na mabubuksan pa ang
    // `state` at hindi na mag-throw ng "Bad state".
    final page = state.currentPage;
    try {
      await _ds.assignCi(
        loanId: loanId,
        riderId: riderId,
        investigationNotes: notes,
        deadline: deadline,
      );
    } catch (e) {
      // Ang TOTOONG dahilan (hal. "Rider is not available") ang itago sa state —
      // dati, kinakain ito ng `catch (_)` kaya generic na "Failed to assign
      // rider" lang ang nakikita kahit malinaw naman ang server error.
      if (!mounted) return false;
      state = state.copyWith(error: ErrorHandler.handle(e).message);
      return false;
    }
    // Ang refresh ay HINDI kasama sa try ng mutation: kung nabigo lang ang
    // reload ng listahan, hindi dapat maging "failed" ang isang matagumpay na
    // assign (dati, `await fetch()` sa loob ng parehong try ang dahilan ng
    // "Failed to assign rider" kahit naisave na sa server).
    if (!mounted) return true;
    await fetch(page: page, silent: true);
    return true;
  }

  Future<bool> assignCI({
    required String loanId,
    required String riderId,
    String notes = '',
    DateTime? deadline,
  }) {
    return assignCi(
      loanId: loanId,
      riderId: riderId,
      notes: notes,
      deadline: deadline?.toIso8601String() ?? '',
    );
  }

  Future<bool> approveReport({required String ciId, String? notes}) async {
    final page = state.currentPage;
    try {
      await _ds.approveCiReport(ciId: ciId, reviewNotes: notes);
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(error: ErrorHandler.handle(e).message);
      return false;
    }
    if (!mounted) return true;
    await fetch(page: page);
    return true;
  }

  Future<bool> rejectReport({required String ciId, required String reason}) async {
    final page = state.currentPage;
    try {
      await _ds.rejectCiReport(ciId: ciId, rejectionReason: reason);
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(error: ErrorHandler.handle(e).message);
      return false;
    }
    if (!mounted) return true;
    await fetch(page: page);
    return true;
  }
}

final hmCiProvider =
    AutoDisposeStateNotifierProvider<HmCiNotifier, HmCiState>((ref) {
  return HmCiNotifier(sl<CiRemoteDataSource>());
});
