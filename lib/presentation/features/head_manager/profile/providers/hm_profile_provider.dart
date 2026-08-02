// lib/presentation/features/head_manager/profile/providers/hm_profile_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/datasources/remote/auth_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';

class HmProfileState {
  final UserModel? user;
  final bool isLoading;
  final String? error;

  const HmProfileState({this.user, this.isLoading = false, this.error});

  HmProfileState copyWith({UserModel? user, bool? isLoading, String? error}) =>
      HmProfileState(
          user: user ?? this.user,
          isLoading: isLoading ?? this.isLoading,
          error: error);
}

class HmProfileNotifier extends StateNotifier<HmProfileState> {
  final UserRemoteDataSource _userDs;
  final AuthRemoteDataSource _authDs;

  HmProfileNotifier(this._userDs, this._authDs)
      : super(const HmProfileState()) {
    loadProfile();
  }

  Future<void> loadProfile() async {
    state = state.copyWith(isLoading: true);
    try {
      final user = await _userDs.getProfile();
      state = state.copyWith(user: user, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> updateProfile(
      {required String firstName, required String lastName}) async {
    await _userDs
        .updateProfile({'first_name': firstName, 'last_name': lastName});
    await loadProfile();
  }

  Future<void> changePassword(
      {required String currentPassword, required String newPassword}) async {
    await _authDs.forceChangePassword(
        currentPassword: currentPassword, newPassword: newPassword);
  }
}

final hmProfileProvider =
    StateNotifierProvider<HmProfileNotifier, HmProfileState>(
  (ref) =>
      HmProfileNotifier(sl<UserRemoteDataSource>(), sl<AuthRemoteDataSource>()),
);
