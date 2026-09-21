// lib/presentation/features/employee/riders/providers/emp_rider_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class EmpRiderState {
  final List<UserModel> riders;
  final bool isLoading;
  final String? error;
  final int total;
  final int totalPages;
  final int page;
  final String search;
  final String statusFilter;
  final String? dateFrom;
  final String? dateTo;

  const EmpRiderState({
    this.riders = const [],
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

  EmpRiderState copyWith({
    List<UserModel>? riders,
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
      EmpRiderState(
        riders: riders ?? this.riders,
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

class EmpRiderStateNotifier extends StateNotifier<EmpRiderState>
    with RealtimeRefreshMixin {
  final UserRemoteDataSource _ds;
  EmpRiderStateNotifier(this._ds) : super(const EmpRiderState()) {
    bindRealtimeRefresh(['users', 'rider_profiles'], refresh: () => load(silent: true));
    load();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final paged = await _ds.getUsersPaged(
        role: 'rider',
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
        riders: filtered,
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

  void setDateRange(String? from, String? to) {
    state = state.copyWith(dateFrom: from, dateTo: to, page: 1);
    load();
  }

  void setStatus(String v) {
    state = state.copyWith(statusFilter: v, page: 1);
    load();
  }

  /// Pagination footer — `TablePagination` (server-side pages).
  void setPage(int p) {
    state = state.copyWith(page: p);
    load(silent: true);
  }

  Future<void> createRider(Map<String, dynamic> data) async {
    await _ds.createRider(data);
    await load(silent: true);
  }

  Future<void> archive(String userId) async {
    await _ds.archive(userId);
    await load();
  }
}

final empRiderProvider =
    AutoDisposeStateNotifierProvider<EmpRiderStateNotifier, EmpRiderState>(
  (ref) => EmpRiderStateNotifier(sl<UserRemoteDataSource>()),
);

// Legacy provider for backward compat
final empRiderListProvider = AutoDisposeStateNotifierProvider<
    EmpRiderLegacyNotifier, AsyncValue<Map<String, dynamic>>>((ref) {
  return EmpRiderLegacyNotifier(sl<UserRemoteDataSource>());
});

class EmpRiderLegacyNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final UserRemoteDataSource _ds;
  EmpRiderLegacyNotifier(this._ds)
      : super(const AsyncData({'items': [], 'total': 0}));

  Future<void> loadList({String? search, String? status, int page = 1}) async {
    state = const AsyncLoading();
    try {
      final list = await _ds.getUsers(
          role: 'rider', search: search, status: status, page: page);
      state = AsyncData({
        'items': list.map((u) => u.toJson()).toList(),
        'total': list.length
      });
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }

  Future<bool> create(Map<String, dynamic> data) async {
    try {
      await _ds.createRider(data);
      await loadList();
      return true;
    } catch (e) {
      return false;
    }
  }
}
