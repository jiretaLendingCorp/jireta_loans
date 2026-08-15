// lib/presentation/features/head_manager/employees/providers/hm_employee_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmEmployeeState {
  final List<UserModel> employees;
  final bool isLoading;
  final String? error;
  final int total;
  final int page;
  final String search;
  final String statusFilter;

  const HmEmployeeState({
    this.employees = const [],
    this.isLoading = false,
    this.error,
    this.total = 0,
    this.page = 1,
    this.search = '',
    this.statusFilter = 'all',
  });

  HmEmployeeState copyWith({
    List<UserModel>? employees,
    bool? isLoading,
    String? error,
    int? total,
    int? page,
    String? search,
    String? statusFilter,
  }) =>
      HmEmployeeState(
        employees: employees ?? this.employees,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        total: total ?? this.total,
        page: page ?? this.page,
        search: search ?? this.search,
        statusFilter: statusFilter ?? this.statusFilter,
      );
}

class HmEmployeeNotifier extends StateNotifier<HmEmployeeState>
    with RealtimeRefreshMixin {
  final UserRemoteDataSource _ds;
  HmEmployeeNotifier(this._ds) : super(const HmEmployeeState()) {
    bindRealtimeRefresh(['users', 'employee_profiles'],
        refresh: () => load(silent: true));
    load();
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true);
    try {
      final list = await _ds.getUsers(
        role: 'employee',
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
        page: state.page,
      );
      state = state.copyWith(employees: list, isLoading: false);
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

  Future<void> createEmployee(Map<String, dynamic> data) async {
    await _ds.createEmployee(data);
    await load();
  }

  Future<void> updateEmployee({
    required String userId,
    String? firstName,
    String? lastName,
    String? middleName,
    String? phone,
    String? department,
    String? position,
    String? gender,
    String? civilStatus,
  }) async {
    await _ds.updateProfile({
      'user_id': userId,
      'first_name': firstName,
      'last_name': lastName,
      'middle_name': middleName,
      'phone_number': phone,
      'department': department,
      'position': position,
      'gender': gender,
      'civil_status': civilStatus,
    });
    await load();
  }

  Future<void> archive(String userId) async {
    await _ds.archive(userId);
    await load();
  }
}

final hmEmployeeProvider =
    AutoDisposeStateNotifierProvider<HmEmployeeNotifier, HmEmployeeState>(
  (ref) => HmEmployeeNotifier(sl<UserRemoteDataSource>()),
);
