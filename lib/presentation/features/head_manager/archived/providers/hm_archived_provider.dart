// lib/presentation/features/head_manager/archived/providers/hm_archived_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmArchivedState {
  final List<UserModel> users;
  final bool isLoading;
  final String? error;
  final String search;
  final String roleFilter;
  final String? dateFrom;
  final String? dateTo;

  const HmArchivedState({
    this.users = const [],
    this.isLoading = false,
    this.error,
    this.search = '',
    this.roleFilter = 'all',
    this.dateFrom,
    this.dateTo,
  });

  HmArchivedState copyWith({
    List<UserModel>? users,
    bool? isLoading,
    String? error,
    String? search,
    String? roleFilter,
    String? dateFrom,
    String? dateTo,
  }) =>
      HmArchivedState(
        users: users ?? this.users,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        search: search ?? this.search,
        roleFilter: roleFilter ?? this.roleFilter,
        dateFrom: dateFrom ?? this.dateFrom,
        dateTo: dateTo ?? this.dateTo,
      );
}

class HmArchivedNotifier extends StateNotifier<HmArchivedState>
    with RealtimeRefreshMixin {
  final UserRemoteDataSource _ds;
  // Guards against out-of-order responses: a slow older request must never
  // overwrite a newer search/filter result (this made the list look stuck on
  // "loading" and hid the actual matches).
  int _requestSeq = 0;

  HmArchivedNotifier(this._ds) : super(const HmArchivedState()) {
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
      final list = await _ds.getUsers(
        role: state.roleFilter == 'all' ? null : state.roleFilter,
        status: 'archived',
        search: state.search.isEmpty ? null : state.search,
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
      );
      if (seq != _requestSeq) {
        return; // stale response — a newer request owns the UI
      }
      state = state.copyWith(users: list, isLoading: false);
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

  void setRole(String v) {
    state = state.copyWith(roleFilter: v);
    load(silent: true);
  }

  void setDateRange(String? from, String? to) {
    state = state.copyWith(dateFrom: from, dateTo: to);
    load(silent: true);
  }

  Future<void> restore(String userId) async {
    try {
      await _ds.unarchive(userId);
    } catch (_) {
      // Fallback for older backend or if unarchive endpoint not yet deployed
      await _ds.updateProfile({
        'user_id': userId,
        'account_status': 'active',
      });
    }
    await load(silent: true);
  }
}

final hmArchivedProvider =
    AutoDisposeStateNotifierProvider<HmArchivedNotifier, HmArchivedState>(
  (ref) => HmArchivedNotifier(sl<UserRemoteDataSource>()),
);
