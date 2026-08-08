// lib/presentation/features/head_manager/riders/providers/hm_rider_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  const HmRiderState({
    this.riders = const [],
    this.isLoading = false,
    this.error,
    this.search = '',
    this.statusFilter = 'all',
  });

  HmRiderState copyWith({
    List<UserModel>? riders,
    bool? isLoading,
    String? error,
    String? search,
    String? statusFilter,
  }) => HmRiderState(
    riders: riders ?? this.riders,
    isLoading: isLoading ?? this.isLoading,
    error: error,
    search: search ?? this.search,
    statusFilter: statusFilter ?? this.statusFilter,
  );
}

class HmRiderNotifier extends StateNotifier<HmRiderState>
    with RealtimeRefreshMixin {
  final UserRemoteDataSource _ds;
  HmRiderNotifier(this._ds) : super(const HmRiderState()) {
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
      );
      state = state.copyWith(riders: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
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

  Future<void> createRider(Map<String, dynamic> data) async {
    await _ds.createRider(data);
    await load();
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
    await load();
  }

  Future<void> suspendActivate(String userId, String action) async {
    await _ds.suspendActivate(userId, action);
    await load();
  }

  Future<void> archive(String userId) async {
    await _ds.archive(userId);
    await load();
  }
}

final hmRiderProvider = StateNotifierProvider<HmRiderNotifier, HmRiderState>(
  (ref) => HmRiderNotifier(sl<UserRemoteDataSource>()),
);
