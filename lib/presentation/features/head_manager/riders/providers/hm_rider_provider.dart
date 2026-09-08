// lib/presentation/features/head_manager/riders/providers/hm_rider_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class HmRiderState {
  final List<UserModel> riders;
  final bool isLoading;
  final String? error;
  final String search;
  final String statusFilter;
  final String? dateFrom;
  final String? dateTo;

  const HmRiderState({
    this.riders = const [],
    this.isLoading = false,
    this.error,
    this.search = '',
    this.statusFilter = 'all',
    this.dateFrom,
    this.dateTo,
  });

  HmRiderState copyWith({
    List<UserModel>? riders,
    bool? isLoading,
    String? error,
    String? search,
    String? statusFilter,
    String? dateFrom,
    String? dateTo,
  }) =>
      HmRiderState(
        riders: riders ?? this.riders,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        search: search ?? this.search,
        statusFilter: statusFilter ?? this.statusFilter,
        dateFrom: dateFrom ?? this.dateFrom,
        dateTo: dateTo ?? this.dateTo,
      );
}

class HmRiderNotifier extends StateNotifier<HmRiderState>
    with RealtimeRefreshMixin {
  final UserRemoteDataSource _ds;
  // Guards against out-of-order responses: a slow older request must never
  // overwrite a newer search/filter result (this made the list look stuck on
  // "loading" and hid the actual matches).
  int _requestSeq = 0;

  HmRiderNotifier(this._ds) : super(const HmRiderState()) {
    bindRealtimeRefresh(['users', 'rider_profiles'],
        refresh: () => load(silent: true));
    load();
  }

  Future<void> load({bool silent = false}) async {
    final seq = ++_requestSeq;
    // Only the very first load (or a reload on an empty list) may replace the
    // whole body with a shimmer. Searches/filters keep the current rows on
    // screen and swap in the new result when it arrives.
    if (!silent && state.riders.isEmpty) {
      state = state.copyWith(isLoading: true, error: null);
    }
    try {
      final list = await _ds.getUsers(
        role: 'rider',
        status: state.statusFilter == 'all' ? null : state.statusFilter,
        search: state.search.isEmpty ? null : state.search,
        dateFrom: state.dateFrom,
        dateTo: state.dateTo,
      );
      if (seq != _requestSeq)
        return; // stale response — a newer request owns the UI
      final filtered = state.statusFilter == 'all'
          ? list.where((u) => u.accountStatus != 'archived').toList()
          : list;
      state = state.copyWith(riders: filtered, isLoading: false);
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

  void setStatus(String v) {
    state = state.copyWith(statusFilter: v);
    load(silent: true);
  }

  void setDateRange(String? from, String? to) {
    state = state.copyWith(dateFrom: from, dateTo: to);
    load(silent: true);
  }

  Future<void> createRider(Map<String, dynamic> data) async {
    await _ds.createRider(data);
    await load(silent: true);
  }

  /// Resets the rider's password to the default (backend forces a change
  /// on next login) — mirrors the employee / head-manager action.
  Future<void> resetPassword(String userId) async {
    await _ds.resetPassword(userId);
    await load(silent: true);
  }

  Future<void> updateRider({
    required String userId,
    String? firstName,
    String? lastName,
    String? phone,
    String? plateNumber,
    String? driversLicenseNumber,
    String? vehicleType,
    String? vehicleBrand,
  }) async {
    await _ds.updateProfile({
      'user_id': userId,
      'first_name': firstName,
      'last_name': lastName,
      'phone_number': phone,
      'plate_number': plateNumber,
      'drivers_license_number': driversLicenseNumber,
      'vehicle_type': vehicleType,
      'vehicle_brand': vehicleBrand,
    });
    await load(silent: true);
  }

  Future<void> archive(String userId) async {
    await _ds.archive(userId);
    await load(silent: true);
  }
}

final hmRiderProvider =
    AutoDisposeStateNotifierProvider<HmRiderNotifier, HmRiderState>(
  (ref) => HmRiderNotifier(sl<UserRemoteDataSource>()),
);
