// lib/presentation/features/rider/profile/providers/rider_profile_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/datasources/remote/auth_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';

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

class RiderProfileNotifier extends StateNotifier<RiderProfileState> {
  final UserRemoteDataSource _ds;
  final AuthRemoteDataSource _authDs;

  RiderProfileNotifier(this._ds, this._authDs)
      : super(const RiderProfileState()) {
    loadProfile();
  }

  Future<void> loadProfile() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _ds.getProfile();
      state = state.copyWith(user: user, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
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
      state = state.copyWith(isSaving: false, error: e.toString());
      return false;
    }
  }

  Future<void> refresh() => loadProfile();

  Future<bool> update(Map<String, dynamic> data) => updateProfile(data);

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    state = state.copyWith(isSaving: true);
    try {
      await _authDs.forceChangePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      state = state.copyWith(isSaving: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSaving: false, error: e.toString());
      return false;
    }
  }
}

final riderProfileProvider =
    StateNotifierProvider<RiderProfileNotifier, RiderProfileState>((ref) {
  return RiderProfileNotifier(
      sl<UserRemoteDataSource>(), sl<AuthRemoteDataSource>());
});
