// lib/presentation/features/rider/profile/providers/rider_profile_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../core/errors/error_handler.dart';
import '../../../../../core/di/injection.dart';
import '../../../../../core/security/secure_storage.dart';
import '../../../../../core/utils/logger.dart';
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
      AppLogger.debug('[RiderProfile] loaded ${user.id} role=${user.role}');
      state = state.copyWith(user: user, isLoading: false, error: null);
    } catch (e, s) {
      AppLogger.e('[RiderProfile] loadProfile failed: $e', e, s);
      if (kDebugMode) debugPrint('[RiderProfile] loadProfile failed: $e');
      final failure = ErrorHandler.handle(e);
      final isNotFound = failure.code == 'NOT_FOUND' ||
          failure.message.toLowerCase().contains('user not found') ||
          e.toString().toLowerCase().contains('user not found');
      if (isNotFound) {
        // Fallback: try stored public id (handles legacy auth/public id mismatch)
        try {
          final storedId = await SecureStorage.getUserId();
          final storedRole = await SecureStorage.getUserRole();
          AppLogger.debug('[RiderProfile] fallback storedId=$storedId role=$storedRole');
          if (storedId != null && storedId.isNotEmpty) {
            try {
              final user2 = await _ds.getProfile(userId: storedId);
              AppLogger.debug('[RiderProfile] fallback with storedId succeeded ${user2.id}');
              state = state.copyWith(user: user2, isLoading: false, error: null);
              return;
            } catch (e2, s2) {
              AppLogger.e('[RiderProfile] fallback with storedId $storedId failed: $e2', e2, s2);
            }
            // Last resort: direct Supabase query bypassing Edge Function (RLS must allow)
            try {
              final supa = Supabase.instance.client;
              final raw = await supa
                  .from('users')
                  .select('id, first_name, middle_name, last_name, suffix, email, phone_number, account_status, profile_photo_url, created_at, last_login_at, roles!users_role_id_fkey!inner(name), rider_profiles(vehicle_type, plate_number, drivers_license_number, vehicle_brand, is_available)')
                  .eq('id', storedId)
                  .maybeSingle();
              if (raw != null) {
                AppLogger.debug('[RiderProfile] direct Supabase fallback succeeded $raw');
                final roleName = (raw['roles'] is Map ? (raw['roles'] as Map)['name'] : null) ?? storedRole ?? 'rider';
                final riderProf = raw['rider_profiles'] is List
                    ? (raw['rider_profiles'] as List).isNotEmpty ? (raw['rider_profiles'] as List).first : null
                    : raw['rider_profiles'];
                final flat = {
                  'id': raw['id'],
                  'role': roleName,
                  'first_name': raw['first_name'],
                  'middle_name': raw['middle_name'],
                  'last_name': raw['last_name'],
                  'suffix': raw['suffix'],
                  'email': raw['email'],
                  'phone_number': raw['phone_number'],
                  'account_status': raw['account_status'],
                  'force_password_change': false,
                  'profile_photo_url': raw['profile_photo_url'],
                  'created_at': raw['created_at'],
                  'last_login_at': raw['last_login_at'],
                  'vehicle_type': riderProf is Map ? riderProf['vehicle_type'] : null,
                  'plate_number': riderProf is Map ? riderProf['plate_number'] : null,
                  'drivers_license_number': riderProf is Map ? riderProf['drivers_license_number'] : null,
                  'vehicle_brand': riderProf is Map ? riderProf['vehicle_brand'] : null,
                };
                final user3 = UserModel.fromJson(flat);
                state = state.copyWith(user: user3, isLoading: false, error: null);
                return;
              }
            } catch (e3, s3) {
              AppLogger.e('[RiderProfile] direct Supabase fallback failed: $e3', e3, s3);
            }
          }
        } catch (_) {}
      }
      if (silent) return;
      final msg = isNotFound
          ? 'Profile not found. Please re-login. If this persists, contact support. (code: ${failure.code ?? '404'} storedId=${await SecureStorage.getUserId() ?? 'null'})'
          : failure.message;
      state = state.copyWith(isLoading: false, error: msg);
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
