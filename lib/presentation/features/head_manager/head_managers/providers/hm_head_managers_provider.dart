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

  const HmHeadManagersState({
    this.users = const [],
    this.isLoading = false,
    this.error,
    this.search = '',
    this.statusFilter = 'all',
  });

  HmHeadManagersState copyWith({
    List<UserModel>? users,
    bool? isLoading,
    String? error,
    String? search,
    String? statusFilter,
  }) =>
      HmHeadManagersState(
        users: users ?? this.users,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        search: search ?? this.search,
        statusFilter: statusFilter ?? this.statusFilter,
      );
}

class HmHeadManagersNotifier extends StateNotifier<HmHeadManagersState>
    with RealtimeRefreshMixin {
  final UserRemoteDataSource _ds;
  HmHeadManagersNotifier(this._ds) : super(const HmHeadManagersState()) {
    bindRealtimeRefresh(['users'], refresh: () => load(silent: true));
    load();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final list = await _ds.getUsers(
        role: 'head_manager',
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
      );
      // Kapag naka "All Status" hindi ipapakita ang archived — nasa Archived container na sila.
      final filtered = state.statusFilter == 'all'
          ? list.where((u) => u.accountStatus != 'archived').toList()
          : list;
      state = state.copyWith(users: filtered, isLoading: false);
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setSearch(String v) {
    state = state.copyWith(search: v);
    load();
  }

  void setStatus(String v) {
    state = state.copyWith(statusFilter: v);
    load();
  }

  Future<Map<String, dynamic>> createHeadManager(
      Map<String, dynamic> data) async {
    final res = await _ds.createHeadManager(data);
    await load();
    return res;
  }

  /// Head Manager resets a user's password to the default (backend forces
  /// a change on next login).
  Future<void> resetPassword(String userId) async {
    await _ds.resetPassword(userId);
    await load();
  }
}

final hmHeadManagersProvider =
    AutoDisposeStateNotifierProvider<HmHeadManagersNotifier, HmHeadManagersState>(
  (ref) => HmHeadManagersNotifier(sl<UserRemoteDataSource>()),
);
