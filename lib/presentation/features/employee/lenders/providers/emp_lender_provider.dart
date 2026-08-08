// lib/presentation/features/employee/lenders/providers/emp_lender_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    bindRealtimeRefresh(['users', 'lender_profiles'], refresh: load);
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final list = await _ds.getUsers(
        role: 'lender',
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
        page: state.page,
      );
      state = state.copyWith(lenders: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
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
}

final empLenderProvider =
    StateNotifierProvider<EmpLenderNotifier, EmpLenderState>(
  (ref) => EmpLenderNotifier(sl<UserRemoteDataSource>()),
);
