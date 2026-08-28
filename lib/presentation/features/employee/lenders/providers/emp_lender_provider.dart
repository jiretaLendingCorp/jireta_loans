// lib/presentation/features/employee/lenders/providers/emp_lender_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class EmpLenderState {
  final List<UserModel> lenders;
  final bool isLoading;
  final String? error;
  final int total;
  final int page;
  final String search;
  final String statusFilter;

  const EmpLenderState({
    this.lenders = const [],
    this.isLoading = false,
    this.error,
    this.total = 0,
    this.page = 1,
    this.search = '',
    this.statusFilter = 'all',
  });

  EmpLenderState copyWith({
    List<UserModel>? lenders,
    bool? isLoading,
    String? error,
    int? total,
    int? page,
    String? search,
    String? statusFilter,
  }) =>
      EmpLenderState(
        lenders: lenders ?? this.lenders,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        total: total ?? this.total,
        page: page ?? this.page,
        search: search ?? this.search,
        statusFilter: statusFilter ?? this.statusFilter,
      );
}

class EmpLenderNotifier extends StateNotifier<EmpLenderState>
    with RealtimeRefreshMixin {
  final UserRemoteDataSource _ds;
  EmpLenderNotifier(this._ds) : super(const EmpLenderState()) {
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
        page: state.page,
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
    state = state.copyWith(search: v, page: 1);
    load();
  }

  void setStatus(String v) {
    state = state.copyWith(statusFilter: v, page: 1);
    load();
  }

  Future<void> createLender(Map<String, dynamic> data) async {
    await _ds.createLender(data);
    await load();
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    await _ds.updateProfile(data);
    await load();
  }

  Future<void> archive(String userId) async {
    await _ds.archive(userId);
    await load();
  }
}

final empLenderProvider =
    AutoDisposeStateNotifierProvider<EmpLenderNotifier, EmpLenderState>(
  (ref) => EmpLenderNotifier(sl<UserRemoteDataSource>()),
);
