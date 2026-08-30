// lib/presentation/features/lender/profile/providers/lender_profile_provider.dart
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
    bindRealtimeRefresh(['users', 'lender_profiles'],
        refresh: () => loadProfile(silent: true));
    loadProfile();
  }

  Future<void> loadProfile({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, error: null);
    try {
      final user = await _ds.getProfile();
      AppLogger.debug('[LenderProfile] loaded ${user.id} role=${user.role}');
      state = state.copyWith(user: user, isLoading: false, error: null);
    } catch (e, s) {
      AppLogger.e('[LenderProfile] loadProfile failed: $e', e, s);
      if (kDebugMode) debugPrint('[LenderProfile] loadProfile failed: $e');
      final failure = ErrorHandler.handle(e);
      final isNotFound = failure.code == 'NOT_FOUND' ||
          failure.message.toLowerCase().contains('user not found') ||
          e.toString().toLowerCase().contains('user not found');
      if (isNotFound) {
        try {
          final storedId = await SecureStorage.getUserId();
          final storedRole = await SecureStorage.getUserRole();
          AppLogger.debug('[LenderProfile] fallback storedId=$storedId role=$storedRole');
          if (storedId != null && storedId.isNotEmpty) {
            try {
              final user2 = await _ds.getProfile(userId: storedId);
              AppLogger.debug('[LenderProfile] fallback with storedId succeeded ${user2.id}');
              state = state.copyWith(user: user2, isLoading: false, error: null);
              return;
            } catch (e2, s2) {
              AppLogger.e('[LenderProfile] fallback with storedId $storedId failed: $e2', e2, s2);
            }
            // Last resort: direct Supabase query
            try {
              final supa = Supabase.instance.client;
              final raw = await supa
                  .from('users')
                  .select('id, first_name, middle_name, last_name, suffix, email, phone_number, account_status, profile_photo_url, created_at, last_login_at, roles!inner(name), lender_profiles(account_upgrade_status, gender, civil_status, date_of_birth, employment_type, employer_name, monthly_income, source_of_funds, gcash_number)')
                  .eq('id', storedId)
                  .maybeSingle();
              if (raw != null) {
                AppLogger.debug('[LenderProfile] direct Supabase fallback succeeded $raw');
                final roleName = (raw['roles'] is Map ? (raw['roles'] as Map)['name'] : null) ?? storedRole ?? 'lender';
                final lenderProf = raw['lender_profiles'] is List
                    ? (raw['lender_profiles'] as List).isNotEmpty ? (raw['lender_profiles'] as List).first : null
                    : raw['lender_profiles'];
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
                  'gender': lenderProf is Map ? lenderProf['gender'] : null,
                  'civil_status': lenderProf is Map ? lenderProf['civil_status'] : null,
                  'date_of_birth': lenderProf is Map ? lenderProf['date_of_birth'] : null,
                  'employment_type': lenderProf is Map ? lenderProf['employment_type'] : null,
                  'employer_name': lenderProf is Map ? lenderProf['employer_name'] : null,
                  'monthly_income': lenderProf is Map ? lenderProf['monthly_income'] : null,
                  'source_of_funds': lenderProf is Map ? lenderProf['source_of_funds'] : null,
                  'gcash_number': lenderProf is Map ? lenderProf['gcash_number'] : null,
                  'account_upgrade_status': lenderProf is Map ? lenderProf['account_upgrade_status'] : null,
                };
                final user3 = UserModel.fromJson(flat);
                state = state.copyWith(user: user3, isLoading: false, error: null);
                return;
              }
            } catch (e3, s3) {
              AppLogger.e('[LenderProfile] direct Supabase fallback failed: $e3', e3, s3);
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
}

final lenderProfileProvider =
    AutoDisposeStateNotifierProvider<LenderProfileNotifier, LenderProfileState>(
        (ref) {
  return LenderProfileNotifier(sl<UserRemoteDataSource>());
});
