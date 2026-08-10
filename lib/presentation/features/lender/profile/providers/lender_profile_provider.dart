// lib/presentation/features/lender/profile/providers/lender_profile_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../data/datasources/remote/user_remote_datasource.dart';
import '../../../../../data/models/user_model.dart';
import '../../../../shared/providers/realtime_refresh_mixin.dart';

class LenderProfileState {
  final UserModel? user;
  final bool isLoading;
  final String? error;
  final bool isSaving;

  const LenderProfileState({
    this.user,
    this.isLoading = false,
    this.error,
    this.isSaving = false,
  });

  LenderProfileState copyWith({
    UserModel? user,
    bool? isLoading,
    String? error,
    bool? isSaving,
  }) =>
      LenderProfileState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isSaving: isSaving ?? this.isSaving,
      );
}

class LenderProfileNotifier extends StateNotifier<LenderProfileState>
    with RealtimeRefreshMixin {
  final UserRemoteDataSource _ds;

  LenderProfileNotifier(this._ds) : super(const LenderProfileState()) {
    bindRealtimeRefresh(['users', 'lender_profiles'], refresh: loadProfile);
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
}

final lenderProfileProvider =
    AutoDisposeStateNotifierProvider<LenderProfileNotifier, LenderProfileState>((ref) {
  return LenderProfileNotifier(sl<UserRemoteDataSource>());
});
