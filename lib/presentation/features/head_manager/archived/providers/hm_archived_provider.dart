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

  const HmArchivedState({
    this.users = const [],
    this.isLoading = false,
    this.error,
    this.search = '',
    this.roleFilter = 'all',
  });

  HmArchivedState copyWith({
    List<UserModel>? users,
    bool? isLoading,
    String? error,
    String? search,
    String? roleFilter,
  }) =>
      HmArchivedState(
        users: users ?? this.users,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        search: search ?? this.search,
        roleFilter: roleFilter ?? this.roleFilter,
      );
}

class HmArchivedNotifier extends StateNotifier<HmArchivedState>
    with RealtimeRefreshMixin {
  final UserRemoteDataSource _ds;
  HmArchivedNotifier(this._ds) : super(const HmArchivedState()) {
    bindRealtimeRefresh(
        ['users', 'rider_profiles', 'lender_profiles', 'employee_profiles'],
        refresh: () => load(silent: true));
    load();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final list = await _ds.getUsers(
        role: state.roleFilter == 'all' ? null : state.roleFilter,
        status: 'archived',
        search: state.search.isEmpty ? null : state.search,
      );
      state = state.copyWith(users: list, isLoading: false);
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

  void setRole(String v) {
    state = state.copyWith(roleFilter: v);
    load();
  }

  Future<void> restore(String userId) async {
    await _ds.updateProfile({
      'user_id': userId,
      'account_status': 'active',
    });
    await load();
  }
}

final hmArchivedProvider =
    AutoDisposeStateNotifierProvider<HmArchivedNotifier, HmArchivedState>(
  (ref) => HmArchivedNotifier(sl<UserRemoteDataSource>()),
);
