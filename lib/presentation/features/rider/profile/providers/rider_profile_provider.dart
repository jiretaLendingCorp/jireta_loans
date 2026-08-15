// lib/presentation/features/rider/profile/providers/rider_profile_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class RiderProfileState {
  final UserModel? user;
  final bool isLoading;
  final String? error;
  final bool isSaving;

  const RiderProfileState({
    this.user,
    this.isLoading = false,
    this.error,
    this.isSaving = false,
  });

  String? get plateNumber => user?.plateNumber;
  String? get licenseNumber => user?.driversLicenseNumber;

  RiderProfileState copyWith({
    UserModel? user,
    bool? isLoading,
    String? error,
    bool? isSaving,
  }) =>
      RiderProfileState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isSaving: isSaving ?? this.isSaving,
      );
}

class RiderProfileNotifier extends StateNotifier<RiderProfileState>
    with RealtimeRefreshMixin {
  final UserRemoteDataSource _ds;

  RiderProfileNotifier(this._ds) : super(const RiderProfileState()) {
    bindRealtimeRefresh(['users', 'rider_profiles'],
        refresh: () => loadProfile(silent: true));
    loadProfile();
  }

  Future<void> loadProfile({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _ds.getProfile();
      state = state.copyWith(user: user, isLoading: false);
    } catch (e) {
      if (silent) return;
      state = state.copyWith(
          isLoading: false, error: ErrorHandler.handle(e).message);
    }
  }

  Future<bool> updateProfile(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true);
    try {
      await _ds.updateProfile(data);
      await loadProfile();
      state = state.copyWith(isSaving: false);
      return true;
    } catch (e) {
      state = state.copyWith(
          isSaving: false, error: ErrorHandler.handle(e).message);
      return false;
    }
  }

  Future<void> refresh() => loadProfile();

  Future<bool> update(Map<String, dynamic> data) => updateProfile(data);
}

final riderProfileProvider =
    AutoDisposeStateNotifierProvider<RiderProfileNotifier, RiderProfileState>(
        (ref) {
  return RiderProfileNotifier(sl<UserRemoteDataSource>());
});
