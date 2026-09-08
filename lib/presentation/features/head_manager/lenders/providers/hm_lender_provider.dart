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
  final String? dateFrom;
  final String? dateTo;

  const HmLenderState({
    this.lenders = const [],
    this.isLoading = false,
    this.error,
    this.search = '',
    this.statusFilter = 'all',
    this.dateFrom,
    this.dateTo,
  });

  HmLenderState copyWith({
    List<UserModel>? lenders,
    bool? isLoading,
    String? error,
    String? search,
    String? statusFilter,
    String? dateFrom,
    String? dateTo,
  }) =>
      HmLenderState(
        lenders: lenders ?? this.lenders,
        isLoading: isLoading ?? this.isLoading,
        error: error,
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
      final list = await _ds.getUsers(
        role: 'lender',
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
      );
      final filtered = state.statusFilter == 'all'
          ? list.where((u) => u.accountStatus != 'archived').toList()
          : list;
      state = state.copyWith(lenders: filtered, isLoading: false);
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

  void setDateRange(String? from, String? to) {
    state = state.copyWith(dateFrom: from, dateTo: to);
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
