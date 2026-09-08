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
  final String? dateFrom;
  final String? dateTo;

  const HmEmployeeState({
    this.employees = const [],
    this.isLoading = false,
    this.error,
    this.total = 0,
    this.page = 1,
    this.search = '',
    this.statusFilter = 'all',
    this.dateFrom,
    this.dateTo,
  });

  HmEmployeeState copyWith({
    List<UserModel>? employees,
    bool? isLoading,
    String? error,
    int? total,
    int? page,
    String? search,
    String? statusFilter,
    String? dateFrom,
    String? dateTo,
  }) =>
      HmEmployeeState(
        employees: employees ?? this.employees,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        total: total ?? this.total,
        page: page ?? this.page,
        search: search ?? this.search,
        statusFilter: statusFilter ?? this.statusFilter,
        dateFrom: dateFrom ?? this.dateFrom,
        dateTo: dateTo ?? this.dateTo,
      );
}

class HmEmployeeNotifier extends StateNotifier<HmEmployeeState>
    with RealtimeRefreshMixin {
  final UserRemoteDataSource _ds;
  // Guards against out-of-order responses: a slow older request must never
  // overwrite a newer search/filter result (this made the list look stuck on
  // "loading" and hid the actual matches).
  int _requestSeq = 0;

  HmEmployeeNotifier(this._ds) : super(const HmEmployeeState()) {
    bindRealtimeRefresh(['users', 'employee_profiles'],
        refresh: () => load(silent: true));
    load();
  }

  Future<void> load({bool silent = false}) async {
    final seq = ++_requestSeq;
    // Only the very first load (or a reload on an empty list) may replace the
    // whole body with a shimmer. Searches/filters keep the current rows on
    // screen and swap in the new result when it arrives.
    if (!silent && state.employees.isEmpty) {
      state = state.copyWith(isLoading: true, error: null);
    }
    try {
      final list = await _ds.getUsers(
        role: 'employee',
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
        page: state.page,
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
      );
      if (seq != _requestSeq)
        return; // stale response — a newer request owns the UI
      final filtered = state.statusFilter == 'all'
          ? list.where((u) => u.accountStatus != 'archived').toList()
          : list;
      state = state.copyWith(employees: filtered, isLoading: false);
    } catch (e) {
      if (seq != _requestSeq) return;
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  void setSearch(String v) {
    state = state.copyWith(search: v, page: 1);
    load(silent: true);
  }

  void setStatus(String v) {
    state = state.copyWith(statusFilter: v, page: 1);
    load(silent: true);
  }

  void setDateRange(String? from, String? to) {
    state = state.copyWith(dateFrom: from, dateTo: to, page: 1);
    load(silent: true);
  }

  Future<void> createEmployee(Map<String, dynamic> data) async {
    await _ds.createEmployee(data);
    // Silent refresh: the modal already shows its own busy state, so the list
    // must not flash a full-screen shimmer just to insert the new row.
    await load(silent: true);
  }

  Future<void> updateEmployee({
    required String userId,
    String? firstName,
    String? lastName,
    String? middleName,
    String? phone,
    String? position,
    String? gender,
    String? civilStatus,
    DateTime? dateOfBirth,
  }) async {
    await _ds.updateProfile({
      'user_id': userId,
      'first_name': firstName,
      'last_name': lastName,
      'middle_name': middleName,
      'phone_number': phone,
      // Staff profile fields use the nested object (flat gender/civil_status
      // would be misread as lender-profile fields, and flat position is not
      // in the allowed list — both were silently lost before).
      'employee_profile': {
        if (position != null && position.trim().isNotEmpty)
          'position': position.trim(),
        if (gender != null && gender.trim().isNotEmpty)
          'gender': gender.trim().toLowerCase(),
        if (civilStatus != null && civilStatus.trim().isNotEmpty)
          'civil_status': civilStatus.trim().toLowerCase(),
        if (dateOfBirth != null)
          'date_of_birth':
              '${dateOfBirth.year}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}',
      },
    });
    await load(silent: true);
  }

  /// Resets the employee's password to the default (backend forces a change
  /// on next login) — same action the Head Managers screen offers.
  Future<void> resetPassword(String userId) async {
    await _ds.resetPassword(userId);
    await load(silent: true);
  }

  Future<void> archive(String userId) async {
    await _ds.archive(userId);
    await load(silent: true);
  }
}

final hmEmployeeProvider =
    AutoDisposeStateNotifierProvider<HmEmployeeNotifier, HmEmployeeState>(
  (ref) => HmEmployeeNotifier(sl<UserRemoteDataSource>()),
);
