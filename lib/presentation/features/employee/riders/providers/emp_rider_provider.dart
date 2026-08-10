// lib/presentation/features/employee/riders/providers/emp_rider_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class EmpRiderState {
  final List<UserModel> riders;
  final bool isLoading;
  final String? error;
  final int total;
  final int page;
  final String search;
  final String statusFilter;

  const EmpRiderState({
    this.riders = const [],
    this.isLoading = false,
    this.error,
    this.total = 0,
    this.page = 1,
    this.search = '',
    this.statusFilter = 'all',
  });

  EmpRiderState copyWith({
    List<UserModel>? riders,
    bool? isLoading,
    String? error,
    int? total,
    int? page,
    String? search,
    String? statusFilter,
  }) =>
      EmpRiderState(
        riders: riders ?? this.riders,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        total: total ?? this.total,
        page: page ?? this.page,
        search: search ?? this.search,
        statusFilter: statusFilter ?? this.statusFilter,
      );
}

class EmpRiderStateNotifier extends StateNotifier<EmpRiderState>
    with RealtimeRefreshMixin {
  final UserRemoteDataSource _ds;
  EmpRiderStateNotifier(this._ds) : super(const EmpRiderState()) {
    bindRealtimeRefresh(['users', 'rider_profiles'], refresh: load);
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final list = await _ds.getUsers(
        role: 'rider',
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
        page: state.page,
      );
      state = state.copyWith(riders: list, isLoading: false);
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

  Future<void> createRider(Map<String, dynamic> data) async {
    await _ds.createRider(data);
    await load();
  }
}

final empRiderProvider =
    AutoDisposeStateNotifierProvider<EmpRiderStateNotifier, EmpRiderState>(
  (ref) => EmpRiderStateNotifier(sl<UserRemoteDataSource>()),
);

// Legacy provider for backward compat
final empRiderListProvider = AutoDisposeStateNotifierProvider<EmpRiderLegacyNotifier,
    AsyncValue<Map<String, dynamic>>>((ref) {
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
