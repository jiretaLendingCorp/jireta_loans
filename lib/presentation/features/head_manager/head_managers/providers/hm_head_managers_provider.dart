// lib/presentation/features/head_manager/head_managers/providers/hm_head_managers_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmHeadManagersState {
  final List<UserModel> users;
  final bool isLoading;
  final String? error;
  final String search;
  final String statusFilter;
  final String? dateFrom;
  final String? dateTo;

  const HmHeadManagersState({
    this.users = const [],
    this.isLoading = false,
    this.error,
    this.search = '',
    this.statusFilter = 'all',
    this.dateFrom,
    this.dateTo,
  });

  HmHeadManagersState copyWith({
    List<UserModel>? users,
    bool? isLoading,
    String? error,
    String? search,
    String? statusFilter,
    String? dateFrom,
    String? dateTo,
  }) =>
      HmHeadManagersState(
        users: users ?? this.users,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        search: search ?? this.search,
        statusFilter: statusFilter ?? this.statusFilter,
        dateFrom: dateFrom ?? this.dateFrom,
        dateTo: dateTo ?? this.dateTo,
      );
}

class HmHeadManagersNotifier extends StateNotifier<HmHeadManagersState>
    with RealtimeRefreshMixin {
  final UserRemoteDataSource _ds;
  // Guards against out-of-order responses: a slow older request must never
  // overwrite a newer search/filter result (this made the list look stuck on
  // "loading" and hid the actual matches).
  int _requestSeq = 0;

  HmHeadManagersNotifier(this._ds) : super(const HmHeadManagersState()) {
    bindRealtimeRefresh(['users'], refresh: () => load(silent: true));
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
      final list = await _ds.getUsers(
        role: 'head_manager',
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
      );
      if (seq != _requestSeq) {
        return; // stale response — a newer request owns the UI
      }
      // Kapag naka "All Status" hindi ipapakita ang archived — nasa Archived container na sila.
      final filtered = state.statusFilter == 'all'
          ? list.where((u) => u.accountStatus != 'archived').toList()
          : list;
      state = state.copyWith(users: filtered, isLoading: false);
    } catch (e) {
      if (seq != _requestSeq) return;
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setSearch(String v) {
    state = state.copyWith(search: v);
    load(silent: true);
  }

  void setStatus(String v) {
    state = state.copyWith(statusFilter: v);
    load(silent: true);
  }

  void setDateRange(String? from, String? to) {
    state = state.copyWith(dateFrom: from, dateTo: to);
    load(silent: true);
  }

  Future<Map<String, dynamic>> createHeadManager(
      Map<String, dynamic> data) async {
    final res = await _ds.createHeadManager(data);
    // Silent refresh: the modal already shows its own busy state, so the list
    // must not flash a full-screen shimmer just to insert the new row.
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

final hmHeadManagersProvider = AutoDisposeStateNotifierProvider<
    HmHeadManagersNotifier, HmHeadManagersState>(
  (ref) => HmHeadManagersNotifier(sl<UserRemoteDataSource>()),
);
