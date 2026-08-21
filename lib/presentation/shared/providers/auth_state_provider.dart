// lib/presentation/shared/providers/auth_state_provider.dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/env_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/role_constants.dart';
import '../../../core/security/jwt_parser.dart';
import '../../../core/security/session_events.dart';
import '../../../core/security/secure_storage.dart';
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
    _sessionExpiredSub = SessionEvents.onSessionExpired.listen((_) {
      _onSessionExpired();
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
          // Schedule refresh-or-logout based on the JWT `exp`. If the token is
          // already expired this runs immediately: a successful refresh keeps
          // the user signed in, a definitive server rejection auto-logs-out,
          // and a network failure keeps the session so the offline overlay
          // (instead of a surprise logout) shows.
          _scheduleExpiryCheck();
          return;
        }
      }
      state = const AuthState(isAuthenticated: false);
    } catch (_) {
      state = const AuthState(isAuthenticated: false);
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
    await SecureStorage.clearAll();
    state = const AuthState(isAuthenticated: false);
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
      if (exp == null) return;
      final now = DateTime.now().toUtc();
      final delay = exp.difference(now) - const Duration(seconds: 4);
      if (!delay.isNegative) {
        _expiryTimer = Timer(delay, _onTokenExpired);
      } else {
        _onTokenExpired();
      }
    } catch (_) {}
  }

  Future<void> _onTokenExpired() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final result = await _tryRefreshSession();
      if (!mounted) return;
      switch (result) {
        case _RefreshResult.success:
          // New tokens stored → schedule from the refreshed expiry.
          _scheduleExpiryCheck();
          break;
        case _RefreshResult.authRejected:
          // Server definitively rejected the refresh token → auto-logout.
          _onSessionExpired();
          break;
        case _RefreshResult.offline:
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

  void _onSessionExpired() {
    if (!state.isAuthenticated) return;
    _expiryTimer?.cancel();
    logout();
  }
}

enum _RefreshResult { success, authRejected, offline }

final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((
  ref,
) {
  return AuthStateNotifier()..initialize();
});
