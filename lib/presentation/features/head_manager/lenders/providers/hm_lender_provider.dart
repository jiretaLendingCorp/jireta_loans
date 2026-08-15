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
  final String search;
  final String statusFilter;

  const HmLenderState({
    this.lenders = const [],
    this.isLoading = false,
    this.error,
    this.search = '',
    this.statusFilter = 'all',
  });

  HmLenderState copyWith({
    List<UserModel>? lenders,
    bool? isLoading,
    String? error,
    String? search,
    String? statusFilter,
  }) =>
      HmLenderState(
        lenders: lenders ?? this.lenders,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        search: search ?? this.search,
        statusFilter: statusFilter ?? this.statusFilter,
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
      final list = await _ds.getUsers(
        role: 'lender',
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
      );
      state = state.copyWith(lenders: list, isLoading: false);
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

  Future<void> createLender(Map<String, dynamic> data) async {
    await _ds.createLender(data);
    await load();
  }

  Future<void> archive(String userId) async {
    await _ds.archive(userId);
    await load();
  }

  Future<void> updateLender({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    await _ds.updateProfile({'user_id': userId, ...data});
    await load();
  }
}

final hmLenderProvider =
    AutoDisposeStateNotifierProvider<HmLenderNotifier, HmLenderState>(
  (ref) => HmLenderNotifier(
    sl<UserRemoteDataSource>(),
  ),
);
