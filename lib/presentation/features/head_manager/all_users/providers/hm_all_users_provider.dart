// lib/presentation/features/head_manager/all_users/providers/hm_all_users_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmAllUsersState {
  final List<UserModel> users;
  final bool isLoading;
  final String? error;
  final int total;
  final int totalPages;
  final int page;
  final String search;
  final String statusFilter;
  final String roleFilter;
  final String? dateFrom;
  final String? dateTo;

  const HmAllUsersState({
    this.users = const [],
    this.isLoading = false,
    this.error,
    this.total = 0,
    this.totalPages = 1,
    this.page = 1,
    this.search = '',
    this.statusFilter = 'all',
    this.roleFilter = 'all',
    this.dateFrom,
    this.dateTo,
  });

  HmAllUsersState copyWith({
    List<UserModel>? users,
    bool? isLoading,
    String? error,
    int? total,
    int? totalPages,
    int? page,
    String? search,
    String? statusFilter,
    String? roleFilter,
    String? dateFrom,
    String? dateTo,
  }) =>
      HmAllUsersState(
        users: users ?? this.users,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        total: total ?? this.total,
        totalPages: totalPages ?? this.totalPages,
        page: page ?? this.page,
        search: search ?? this.search,
        statusFilter: statusFilter ?? this.statusFilter,
        roleFilter: roleFilter ?? this.roleFilter,
        dateFrom: dateFrom ?? this.dateFrom,
        dateTo: dateTo ?? this.dateTo,
      );
}

class HmAllUsersNotifier extends StateNotifier<HmAllUsersState>
    with RealtimeRefreshMixin {
  final UserRemoteDataSource _ds;
  // Guards against out-of-order responses: a slow older request must never
  // overwrite a newer search/filter result (this made the list look stuck on
  // "loading" and hid the actual matches).
  int _requestSeq = 0;

  HmAllUsersNotifier(this._ds) : super(const HmAllUsersState()) {
    bindRealtimeRefresh(
        ['users', 'rider_profiles', 'lender_profiles', 'employee_profiles'],
        refresh: () => load(silent: true));
    load();
  }

  Future<void> load({bool silent = false}) async {
    final seq = ++_requestSeq;
    // Only the very first load (or a reload on an empty list) may replace the
    // whole body with a shimmer. Searches/filters keep the current rows on
    // screen and swap in the new result when it arrives.
    if (!silent && state.users.isEmpty) {
      state = state.copyWith(isLoading: true, error: null);
    }
    try {
      final paged = await _ds.getUsersPaged(
        role: state.roleFilter == 'all' ? null : state.roleFilter,
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
        page: state.page,
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
      );
      if (seq != _requestSeq) {
        return; // stale response — a newer request owns the UI
      }
      // Naubos ang huling page (hal. na-archive ang huling row) — bumalik sa
      // huling page na may laman imbes na blangkong table.
      if (paged.items.isEmpty && state.page > 1) {
        state = state.copyWith(page: state.page - 1);
        return load(silent: true);
      }
      // Kapag naka "All Status" hindi ipapakita ang archived — nasa Archived container na sila.
      final filtered = state.statusFilter == 'all'
          ? paged.items.where((u) => u.accountStatus != 'archived').toList()
          : paged.items;
      state = state.copyWith(
        users: filtered,
        isLoading: false,
        total: paged.total,
        totalPages: paged.totalPages,
      );
    } catch (e) {
      if (seq != _requestSeq) return;
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setSearch(String v) {
    state = state.copyWith(search: v, page: 1);
    load(silent: true);
  }

  void setStatus(String v) {
    state = state.copyWith(statusFilter: v, page: 1);
    load(silent: true);
  }

  void setRole(String v) {
    state = state.copyWith(roleFilter: v, page: 1);
    load(silent: true);
  }

  void setDateRange(String? from, String? to) {
    state = state.copyWith(dateFrom: from, dateTo: to, page: 1);
    load(silent: true);
  }

  /// Pagination footer — `TablePagination` (server-side pages).
  void setPage(int p) {
    state = state.copyWith(page: p);
    load(silent: true);
  }

  Future<void> archive(String userId) async {
    await _ds.archive(userId);
    await load(silent: true);
  }

  Future<Map<String, dynamic>> createHeadManager(
      Map<String, dynamic> data) async {
    final res = await _ds.createHeadManager(data);
    await load(silent: true);
    return res;
  }

  /// Head Manager resets a user's password to the default (backend forces
  /// a change on next login).
  Future<void> resetPassword(String userId) async {
    await _ds.resetPassword(userId);
    await load(silent: true);
  }
}

final hmAllUsersProvider =
    AutoDisposeStateNotifierProvider<HmAllUsersNotifier, HmAllUsersState>(
  (ref) => HmAllUsersNotifier(sl<UserRemoteDataSource>()),
);
