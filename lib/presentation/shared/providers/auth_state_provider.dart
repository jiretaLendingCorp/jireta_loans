// lib/presentation/shared/providers/auth_state_provider.dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/env_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/role_constants.dart';
import '../../../core/security/jwt_parser.dart';
import '../../../core/security/session_events.dart';
import '../../../core/security/secure_storage.dart';
import '../../../core/services/realtime_service.dart';
import '../../../core/utils/logger.dart';
import '../../../data/models/user_model.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final UserModel? user;
  final String? error;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.user,
    this.error,
  });

  String? get role => user?.role;
  bool get forcePasswordChange => user?.forcePasswordChange ?? false;

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    UserModel? user,
    String? error,
  }) =>
      AuthState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        isLoading: isLoading ?? this.isLoading,
        user: user ?? this.user,
        error: error,
      );
}

class AuthStateNotifier extends StateNotifier<AuthState> {
  AuthStateNotifier() : super(const AuthState()) {
    _sessionExpiredSub = SessionEvents.onSessionExpired.listen((_) async {
      await _onSessionExpired();
    });
  }

  StreamSubscription<void>? _sessionExpiredSub;
  Timer? _expiryTimer;
  bool _isRefreshing = false;

  @override
  void dispose() {
    _sessionExpiredSub?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> initialize() async {
    state = state.copyWith(isLoading: true);
    try {
      final hasSession = await SecureStorage.hasValidSession();
      if (hasSession) {
        final userId = await SecureStorage.getUserId();
        final role = await SecureStorage.getUserRole();
        if (userId != null &&
            role != null &&
            RoleConstants.allRoles.contains(role)) {
          // ── Fix: if the stored access token is already expired (e.g. web tab
          // reopened after 1h), try to refresh BEFORE declaring the user
          // authenticated. This avoids a flash of the dashboard followed by an
          // immediate auto-logout. Offline keeps the session (overlay instead).
          final accessToken = await SecureStorage.getAccessToken();
          final exp = JwtParser.expiry(accessToken);
          if (exp != null && DateTime.now().toUtc().isAfter(exp)) {
            if (kDebugMode) debugPrint('[JWT] initialize: stored token already expired, trying refresh');
            AppLogger.debug('[JWT] initialize: token expired, pre-refresh');
            final preResult = await _tryRefreshSession();
            switch (preResult) {
              case _RefreshResult.authRejected:
                if (kDebugMode) debugPrint('[JWT] initialize: pre-refresh rejected → auto-logout, allow re-login');
                AppLogger.debug('[JWT] initialize: refresh rejected → clear session for re-login');
                await SecureStorage.clearAll();
                try {
                  await Supabase.instance.client.auth.signOut();
                } catch (_) {}
                state = const AuthState(isAuthenticated: false);
                return;
              case _RefreshResult.offline:
                if (kDebugMode) debugPrint('[JWT] initialize: offline, keep session, show overlay');
                // Keep authenticated; timer will retry in 30s via _scheduleExpiryCheck
                break;
              case _RefreshResult.success:
                if (kDebugMode) debugPrint('[JWT] initialize: pre-refresh success, continue authenticated');
                break;
            }
          }
          state = AuthState(
            isAuthenticated: true,
            user: UserModel(
              id: userId,
              role: role,
              firstName: '',
              lastName: '',
              accountStatus: 'active',
              forcePasswordChange: false,
              createdAt: DateTime.now(),
            ),
          );
          // Schedule refresh-or-logout based on the (possibly refreshed) JWT `exp`.
          _scheduleExpiryCheck();
          return;
        }
      }
      state = const AuthState(isAuthenticated: false);
    } catch (e) {
      if (kDebugMode) debugPrint('[JWT] initialize error: $e');
      state = const AuthState(isAuthenticated: false);
    } finally {
      // Ensure loading flag is always cleared so router can redirect to login.
      if (state.isLoading) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  void setAuthenticated(UserModel user) {
    _expiryTimer?.cancel();
    state = AuthState(isAuthenticated: true, user: user);
    _scheduleExpiryCheck();
  }

  void setForcePasswordChangeDone() {
    if (state.user != null) {
      state = state.copyWith(
        user: state.user!.copyWith(forcePasswordChange: false),
      );
    }
  }

  Future<void> logout() async {
    _expiryTimer?.cancel();
    _isRefreshing = false;
    try {
      await RealtimeService.instance.disconnect();
    } catch (_) {}
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    await SecureStorage.clearAll();
    if (mounted) {
      state = const AuthState(isAuthenticated: false);
    } else {
      state = const AuthState(isAuthenticated: false);
    }
    AppLogger.debug('[JWT] logout complete → will redirect to login (re-login enabled)');
    if (kDebugMode) debugPrint('[AuthState] logout: session cleared, ready for re-login');
  }

  /// Schedules an automatic refresh-or-logout at the access token's `exp`
  /// claim (with a small grace period so no in-flight request slips through
  /// with a stale token).
  void _scheduleExpiryCheck() {
    _expiryTimer?.cancel();
    _checkTokenExpiry();
  }

  Future<void> _checkTokenExpiry() async {
    try {
      final accessToken = await SecureStorage.getAccessToken();
      final exp = JwtParser.expiry(accessToken);
      if (exp == null) {
        if (kDebugMode) debugPrint('[JWT] no exp claim → skip auto-logout timer');
        return;
      }
      final now = DateTime.now().toUtc();
      final delay = exp.difference(now) - const Duration(seconds: 4);
      final secs = delay.inSeconds;
      if (kDebugMode) {
        debugPrint(
          '[JWT] exp=$exp now=$now delay=${secs}s isUtc=${exp.isUtc} → ${delay.isNegative ? "already expired → immediate refresh" : "schedule timer"}',
        );
      }
      AppLogger.debug('[JWT] token exp=$exp isUtc=${exp.isUtc} delay=${secs}s');
      if (!delay.isNegative) {
        _expiryTimer = Timer(delay, _onTokenExpired);
        if (kDebugMode) debugPrint('[JWT] expiry timer scheduled for ${delay.inSeconds}s');
      } else {
        // Already expired (e.g. tab reopened after 1h) → try refresh immediately
        _onTokenExpired();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[JWT] _checkTokenExpiry error: $e');
    }
  }

  Future<void> _onTokenExpired() async {
    if (_isRefreshing) {
      if (kDebugMode) debugPrint('[JWT] _onTokenExpired skipped (already refreshing)');
      return;
    }
    _isRefreshing = true;
    if (kDebugMode) debugPrint('[JWT] token expired → attempting refresh...');
    AppLogger.debug('[JWT] token expired, attempting refresh');
    try {
      final result = await _tryRefreshSession();
      if (!mounted) return;
      switch (result) {
        case _RefreshResult.success:
          if (kDebugMode) debugPrint('[JWT] refresh success → reschedule timer');
          AppLogger.debug('[JWT] refresh success, new exp scheduled');
          // New tokens stored → schedule from the refreshed expiry.
          _scheduleExpiryCheck();
          break;
        case _RefreshResult.authRejected:
          if (kDebugMode) debugPrint('[JWT] refresh rejected → auto-logout web app');
          AppLogger.debug('[JWT] refresh rejected → auto-logout');
          // Server definitively rejected the refresh token → auto-logout.
          await _onSessionExpired();
          break;
        case _RefreshResult.offline:
          if (kDebugMode) debugPrint('[JWT] offline during refresh → retry 30s, keep session');
          AppLogger.debug('[JWT] offline, keep session, retry in 30s');
          // No connection (token still stored). Keep the session so the
          // offline overlay shows; retry shortly instead of logging out.
          if (mounted) {
            _expiryTimer?.cancel();
            _expiryTimer = Timer(const Duration(seconds: 30), _onTokenExpired);
          }
          break;
      }
    } finally {
      _isRefreshing = false;
    }
  }

  /// One-shot token refresh used by the expiry scheduler. Kept independent of
  /// [AuthInterceptor] so expired-token detection works even while the app is
  /// idle and no request is being made.
  Future<_RefreshResult> _tryRefreshSession() async {
    final refreshToken = await SecureStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return _RefreshResult.authRejected;
    }
    try {
      final dio = Dio(BaseOptions(
        baseUrl: '${EnvConfig.edgeFunctionsUrl}/',
        connectTimeout: const Duration(milliseconds: 10000),
        receiveTimeout: const Duration(milliseconds: 10000),
        sendTimeout: const Duration(milliseconds: 10000),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'apikey': EnvConfig.supabaseAnonKey,
          // The gateway verifies the bearer before the function runs; without
          // a valid JWT the refresh is rejected at the edge and the session
          // can never recover. The anon key always passes; auth-session then
          // validates the refresh_token itself via the admin client.
          'Authorization': 'Bearer ${EnvConfig.supabaseAnonKey}',
        },
      ));
      final response = await dio.post(
        AppConstants.authRefreshPath,
        data: {'refresh_token': refreshToken},
      );
      final newAccessToken = response.data['access_token'];
      final newRefreshToken = response.data['refresh_token'];
      if (newAccessToken == null || newAccessToken is! String) {
        return _RefreshResult.authRejected;
      }
      await SecureStorage.saveTokens(
        accessToken: newAccessToken,
        refreshToken:
            newRefreshToken is String ? newRefreshToken : refreshToken,
      );
      return _RefreshResult.success;
    } on DioException catch (e) {
      // Server responded → the refresh token is invalid/expired.
      if (e.response != null) return _RefreshResult.authRejected;
      // Transport-level failure → offline / unreachable.
      return _RefreshResult.offline;
    } catch (_) {
      return _RefreshResult.authRejected;
    }
  }

  Future<void> _onSessionExpired() async {
    if (!state.isAuthenticated) {
      if (kDebugMode) debugPrint('[JWT] _onSessionExpired ignored (already logged out)');
      return;
    }
    if (kDebugMode) debugPrint('[JWT] session expired → auto-logout + clear storage → allow re-login');
    AppLogger.debug('[JWT] session expired → auto-logout');
    _expiryTimer?.cancel();
    await logout();
    // Emit is already done by the caller (AuthInterceptor); but if the timer
    // path triggered this, we need to ensure the stream fires for any other listeners.
    // (No double-emit harm – broadcast stream deduplicates via state check).
  }
}

enum _RefreshResult { success, authRejected, offline }

final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((
  ref,
) {
  return AuthStateNotifier()..initialize();
});
