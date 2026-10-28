// lib/presentation/features/head_manager/lenders/providers/hm_lender_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmLenderState {
  final List<UserModel> lenders;
  final bool isLoading;
  final String? error;
  final int total;
  final int totalPages;
  final int page;
  final String search;
  final String statusFilter;
  final String? dateFrom;
  final String? dateTo;

  const HmLenderState({
    this.lenders = const [],
    this.isLoading = false,
    this.error,
    this.total = 0,
    this.totalPages = 1,
    this.page = 1,
    this.search = '',
    this.statusFilter = 'all',
    this.dateFrom,
    this.dateTo,
  });

  HmLenderState copyWith({
    List<UserModel>? lenders,
    bool? isLoading,
    String? error,
    int? total,
    int? totalPages,
    int? page,
    String? search,
    String? statusFilter,
    String? dateFrom,
    String? dateTo,
  }) =>
      HmLenderState(
        lenders: lenders ?? this.lenders,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        total: total ?? this.total,
        totalPages: totalPages ?? this.totalPages,
        page: page ?? this.page,
        search: search ?? this.search,
        statusFilter: statusFilter ?? this.statusFilter,
        dateFrom: dateFrom ?? this.dateFrom,
        dateTo: dateTo ?? this.dateTo,
      );
}

class HmLenderNotifier extends StateNotifier<HmLenderState>
    with RealtimeRefreshMixin {
  final UserRemoteDataSource _ds;
  HmLenderNotifier(this._ds) : super(const HmLenderState()) {
    bindRealtimeRefresh(['users', 'lender_profiles'],
        refresh: () => load(silent: true));
    load();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final paged = await _ds.getUsersPaged(
        role: 'lender',
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
        page: state.page,
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
      );
      // Naubos ang huling page (hal. na-archive ang huling row) — bumalik sa
      // huling page na may laman imbes na blangkong table.
      if (paged.items.isEmpty && state.page > 1) {
        state = state.copyWith(page: state.page - 1);
        return load(silent: true);
      }
      final filtered = state.statusFilter == 'all'
          ? paged.items.where((u) => u.accountStatus != 'archived').toList()
          : paged.items;
      state = state.copyWith(
        lenders: filtered,
        isLoading: false,
        total: paged.total,
        totalPages: paged.totalPages,
      );
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setSearch(String v) {
    state = state.copyWith(search: v, page: 1);
    load();
  }

  void setStatus(String v) {
    state = state.copyWith(statusFilter: v, page: 1);
    load();
  }

  void setDateRange(String? from, String? to) {
    state = state.copyWith(dateFrom: from, dateTo: to, page: 1);
    load();
  }

  /// Pagination footer — `TablePagination` (server-side pages).
  void setPage(int p) {
    state = state.copyWith(page: p);
    load(silent: true);
  }

  Future<void> createLender(Map<String, dynamic> data) async {
    await _ds.createLender(data);
    await load();
  }

  /// Ini-archive ang lender at tinatanggal lang ang row niya sa listahan —
  /// hindi na nire-reload ang buong paged data (na dati ay nagpapakita ng
  /// shimmer sa buong table kahit isang row lang ang na-archive).
  Future<void> archive(String userId) async {
    await _ds.archive(userId);
    final index = state.lenders.indexWhere((l) => l.id == userId);
    if (index == -1) {
      // Wala sa kasalukuyang page/filter — saka lang mag-silent refresh.
      await load(silent: true);
      return;
    }
    final next = List<UserModel>.of(state.lenders)..removeAt(index);
    // Sa 'all' filter, archived users ay hindi binibilang sa server total
    // (kasama pa rin sila doon), kaya dun lang hindi binabawasan ang count.
    final nextTotal = state.statusFilter == 'all' || state.total == 0
        ? state.total
        : state.total - 1;
    state = state.copyWith(lenders: next, total: nextTotal);
    // Naubos ang page — lumipat sa nakaraang page na may laman.
    if (next.isEmpty && state.page > 1) {
      state = state.copyWith(page: state.page - 1);
      await load(silent: true);
    }
  }

  Future<void> updateLender({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    await _ds.updateProfile({'user_id': userId, ...data});
    await load();
  }

  /// I-patch lang sa listahan ang na-edit na lender — hindi na nire-reload ang
  /// buong paged data (na dati ay nagpapakita ng shimmer at bumabalik sa
  /// server kahit isang row lang ang nabago).
  void replaceLender(UserModel updated) {
    final index = state.lenders.indexWhere((l) => l.id == updated.id);
    if (index == -1) {
      // Wala na sa kasalukuyang page/filter — saka lang mag-silent refresh.
      load(silent: true);
      return;
    }
    final next = List<UserModel>.of(state.lenders);
    next[index] = updated;
    state = state.copyWith(lenders: next);
  }
}

final hmLenderProvider =
    AutoDisposeStateNotifierProvider<HmLenderNotifier, HmLenderState>(
  (ref) => HmLenderNotifier(
    sl<UserRemoteDataSource>(),
  ),
);
