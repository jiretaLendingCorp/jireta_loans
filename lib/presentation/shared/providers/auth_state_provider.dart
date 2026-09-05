// lib/presentation/shared/providers/auth_state_provider.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/role_constants.dart';
import '../../../core/security/jwt_parser.dart';
import '../../../core/security/session_events.dart';
import '../../../core/security/session_refresher.dart';
import '../../../core/security/secure_storage.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/services/realtime_service.dart';
import '../../../core/utils/logger.dart';
import '../../../data/models/user_model.dart';

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final bool isLoggingOut;
  final UserModel? user;
  final String? error;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading = false,
    this.isLoggingOut = false,
    this.user,
    this.error,
  });

  String? get role => user?.role;
  bool get forcePasswordChange => user?.forcePasswordChange ?? false;

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isLoading,
    bool? isLoggingOut,
    UserModel? user,
    String? error,
  }) =>
      AuthState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        isLoading: isLoading ?? this.isLoading,
        isLoggingOut: isLoggingOut ?? this.isLoggingOut,
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
  int _authRevision = 0;
  DateTime? _lastActivityPush;

  @override
  void dispose() {
    _sessionExpiredSub?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  /// Called by [SessionIdleDetector] and [AuthInterceptor] on any user
  /// gesture or authenticated API call.  Throttled to once per 10s and
  /// bumps `last_activity_at` forward, resetting the 10-minute idle window.
  Future<void> notifyActivity() async {
    if (!state.isAuthenticated) return;
    final now = DateTime.now().toUtc();
    if (_lastActivityPush != null &&
        now.difference(_lastActivityPush!).inSeconds < 10) {
      return;
    }
    _lastActivityPush = now;
    try {
      await SecureStorage.saveLastActivity(now);
    } catch (_) {}
    _scheduleExpiryCheck();
  }

  Future<void> initialize() async {
    final revision = _authRevision;
    state = state.copyWith(isLoading: true);
    try {
      // ── 10-minute idle session check ───────────────────────────────────
      // hasValidSession now checks both token existence AND idle expiry.
      final hasSession = await SecureStorage.hasValidSession();
      if (revision != _authRevision || !mounted) return;
      if (hasSession) {
        final userId = await SecureStorage.getUserId();
        final role = await SecureStorage.getUserRole();
        if (revision != _authRevision || !mounted) return;
        if (userId != null &&
            role != null &&
            RoleConstants.allRoles.contains(role)) {
          // ── Idle check before auto-login ───────────────────────────────
          // 10s grace to avoid clock-skew false logout right after login.
          final remaining = await SecureStorage.getRemainingIdleTime();
          if (remaining != null && remaining.inSeconds <= -10) {
            if (kDebugMode) debugPrint('[JWT] initialize: idle 10m expired → hard logout, require re-login');
            AppLogger.debug('[JWT] initialize: idle 10m expired → clear for re-login');
            await SecureStorage.clearAll();
            try {
              await Supabase.instance.client.auth.signOut();
            } catch (_) {}
            if (revision != _authRevision || !mounted) return;
            state = const AuthState(isAuthenticated: false);
            return;
          }

          // Legacy migration: if no idle timestamp but token exists, infer from JWT
          if (remaining == null) {
            final accessToken = await SecureStorage.getAccessToken();
            final exp = JwtParser.expiry(accessToken);
            if (exp != null) {
              // Infer lastActivity = exp - 10m (idle window) so remaining makes sense
              final inferredStart = exp.subtract(AppConstants.sessionDuration);
              final now = DateTime.now().toUtc();
              if (now.isBefore(exp)) {
                await SecureStorage.saveSessionStartedAt(inferredStart);
                await SecureStorage.saveLastActivity(inferredStart);
                if (kDebugMode) debugPrint('[JWT] initialize: migrated legacy session lastActivity=$inferredStart exp=$exp');
              } else {
                if (kDebugMode) debugPrint('[JWT] initialize: legacy JWT expired, trying soft refresh');
                AppLogger.debug('[JWT] initialize: legacy JWT expired, pre-refresh');
                final preResult = await _tryRefreshSession();
                if (revision != _authRevision || !mounted) return;
                if (preResult == SessionRefreshResult.authRejected) {
                  await SecureStorage.clearAll();
                  try { await Supabase.instance.client.auth.signOut(); } catch (_) {}
                  if (revision != _authRevision || !mounted) return;
                  state = const AuthState(isAuthenticated: false);
                  return;
                } else if (preResult == SessionRefreshResult.success) {
                  await SecureStorage.saveLastActivity(DateTime.now().toUtc());
                } else {
                  // offline → keep session, timer will retry
                }
              }
            }
          } else {
            // Idle still valid but JWT may be soft-expired
            final accessToken = await SecureStorage.getAccessToken();
            if (JwtParser.isExpired(accessToken) || JwtParser.isExpiringSoon(accessToken, within: const Duration(seconds: 60))) {
              if (remaining.inSeconds > 30) {
                if (kDebugMode) debugPrint('[JWT] initialize: JWT soft-expired but idle valid (${remaining.inSeconds}s left) → soft refresh');
                AppLogger.debug('[JWT] initialize: soft JWT expired, pre-refresh');
                final preResult = await _tryRefreshSession();
                if (revision != _authRevision || !mounted) return;
                switch (preResult) {
                  case SessionRefreshResult.authRejected:
                    if (kDebugMode) debugPrint('[JWT] initialize: soft refresh rejected → hard logout');
                    AppLogger.debug('[JWT] initialize: soft refresh rejected → clear');
                    await SecureStorage.clearAll();
                    try { await Supabase.instance.client.auth.signOut(); } catch (_) {}
                    if (revision != _authRevision || !mounted) return;
                    state = const AuthState(isAuthenticated: false);
                    return;
                  case SessionRefreshResult.offline:
                    if (kDebugMode) debugPrint('[JWT] initialize: offline during soft refresh, keep session');
                    break;
                  case SessionRefreshResult.success:
                    if (kDebugMode) debugPrint('[JWT] initialize: soft refresh success, continue');
                    // Refresh does not extend idle; lastActivity stays as-is
                    break;
                }
              } else {
                if (kDebugMode) debugPrint('[JWT] initialize: JWT expired and idle almost done (${remaining.inSeconds}s) → will hard logout');
              }
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
          // Schedule idle 10m expiry (or soft JWT refresh if JWT sooner)
          _scheduleExpiryCheck();
          return;
        }
      }
      if (revision != _authRevision || !mounted) return;
      state = const AuthState(isAuthenticated: false);
    } catch (e) {
      if (kDebugMode) debugPrint('[JWT] initialize error: $e');
      if (revision != _authRevision || !mounted) return;
      state = const AuthState(isAuthenticated: false);
    } finally {
      if (revision == _authRevision && mounted && state.isLoading) {
        state = state.copyWith(isLoading: false);
      }
    }
  }

  void startInteractiveAuth() {
    _authRevision++;
    _expiryTimer?.cancel();
    if (state.isLoading) {
      state = state.copyWith(isLoading: false);
    }
  }

  void setAuthenticated(UserModel user) {
    _authRevision++;
    _expiryTimer?.cancel();
    state = AuthState(isAuthenticated: true, user: user);
    _scheduleExpiryCheck();
    // Register this device's FCM token for push delivery (fire-and-forget).
    unawaited(FcmService.instance.syncWithUser());
  }

  void setForcePasswordChangeDone() {
    if (state.user != null) {
      state = state.copyWith(
        user: state.user!.copyWith(forcePasswordChange: false),
      );
    }
  }

  Future<void> logout() async {
    _authRevision++;
    _expiryTimer?.cancel();
    _isRefreshing = false;
    // Show global logout loading immediately — visible across web + mobile.
    if (mounted) {
      state = state.copyWith(isLoggingOut: true);
    } else {
      state = state.copyWith(isLoggingOut: true);
    }
    try {
      try {
        await RealtimeService.instance.disconnect();
      } catch (_) {}
      // Deactivate this device's FCM token BEFORE wiping storage so the auth
      // header is still available. Bounded so logout is never blocked by a
      // slow/offline network. Best effort — unregister swallows its own errors.
      try {
        await FcmService.instance.unregister().timeout(
              const Duration(seconds: 3),
            );
      } catch (_) {}
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      await SecureStorage.clearAll();
    } finally {
      if (mounted) {
        state = const AuthState(isAuthenticated: false, isLoggingOut: false);
      } else {
        state = const AuthState(isAuthenticated: false, isLoggingOut: false);
      }
      AppLogger.debug('[JWT] logout complete → will redirect to login (re-login enabled)');
      if (kDebugMode) debugPrint('[AuthState] logout: session cleared, ready for re-login');
    }
  }

  /// Schedules idle logout at 10-minute inactivity expiry.
  /// Within the 10-minute window, if JWT soft-expires before idle, we do a
  /// soft refresh that does NOT extend the idle deadline.
  void _scheduleExpiryCheck() {
    _expiryTimer?.cancel();
    _checkTokenExpiry();
  }

  Future<void> _checkTokenExpiry() async {
    try {
      final remaining = await SecureStorage.getRemainingIdleTime();
      final accessToken = await SecureStorage.getAccessToken();
      final jwtExp = JwtParser.expiry(accessToken);
      final now = DateTime.now().toUtc();

      // ── Case 1: No idle timestamp (legacy) → fallback to JWT ────────────
      if (remaining == null) {
        if (jwtExp == null) {
          if (kDebugMode) debugPrint('[JWT] no idle & no exp claim → skip timer (legacy, wait for user action)');
          return;
        }
        final delay = jwtExp.difference(now) - const Duration(seconds: 4);
        if (kDebugMode) debugPrint('[JWT] legacy fallback: exp=$jwtExp now=$now delay=${delay.inSeconds}s → ${delay.isNegative ? "already expired" : "schedule soft timer"}');
        AppLogger.debug('[JWT] legacy JWT exp=$jwtExp delay=${delay.inSeconds}s');
        if (!delay.isNegative) {
          _expiryTimer = Timer(delay, _onSoftTokenExpired);
          if (kDebugMode) debugPrint('[JWT] legacy soft timer scheduled for ${delay.inSeconds}s');
        } else {
          _onSoftTokenExpired();
        }
        return;
      }

      // ── Case 2: Idle session already expired → hard logout ─────────────
      // 10s grace prevents immediate logout due to event-loop lag.
      if (remaining.inSeconds <= -10) {
        if (kDebugMode) debugPrint('[JWT] idle 10m expired → hard logout immediately');
        AppLogger.debug('[JWT] idle 10m expired, hard logout');
        _onIdleExpired();
        return;
      }

      final idleExpiry = now.add(remaining);
      if (kDebugMode) debugPrint('[JWT] idle remaining=${remaining.inSeconds}s expiry=$idleExpiry');

      // ── Case 3: Idle valid, check JWT soft expiry ──────────────────────
      if (jwtExp != null) {
        final jwtRemaining = jwtExp.difference(now);
        final jwtDelay = jwtRemaining - const Duration(seconds: 4);
        if (kDebugMode) debugPrint('[JWT] jwtExp=$jwtExp jwtRemaining=${jwtRemaining.inSeconds}s jwtDelay=${jwtDelay.inSeconds}s idleRemaining=${remaining.inSeconds}s');

        // JWT soft-expired but idle still has time → soft refresh (no extension of idle)
        if (jwtDelay.isNegative) {
          if (remaining.inSeconds > 10) {
            if (kDebugMode) debugPrint('[JWT] JWT soft-expired but idle valid (${remaining.inSeconds}s left) → soft refresh now');
            _onSoftTokenExpired();
          } else {
            // Idle about to expire (<10s) → just wait for idle logout
            if (kDebugMode) debugPrint('[JWT] JWT expired and idle almost done (${remaining.inSeconds}s) → schedule idle logout');
            _expiryTimer = Timer(remaining, _onIdleExpired);
          }
          return;
        }

        // Both valid: schedule timer for whichever comes first
        // If JWT soft expiry is within 10s of idle expiry, skip refresh and go straight to idle logout
        final Duration nextDelay;
        final bool isJwtSooner;
        if (jwtDelay < remaining) {
          final gap = remaining - jwtDelay;
          if (gap.inSeconds <= 10 || remaining.inSeconds < 60) {
            nextDelay = remaining;
            isJwtSooner = false;
          } else {
            nextDelay = jwtDelay;
            isJwtSooner = true;
          }
        } else {
          nextDelay = remaining;
          isJwtSooner = false;
        }

        if (kDebugMode) debugPrint('[JWT] next timer in ${nextDelay.inSeconds}s → ${isJwtSooner ? "soft JWT refresh" : "idle 10m logout"}');
        AppLogger.debug('[JWT] schedule next in ${nextDelay.inSeconds}s isJwtSooner=$isJwtSooner');

        if (isJwtSooner) {
          _expiryTimer = Timer(nextDelay, _onSoftTokenExpired);
        } else {
          _expiryTimer = Timer(nextDelay, _onIdleExpired);
        }
      } else {
        // No JWT exp claim → just schedule idle expiry
        if (kDebugMode) debugPrint('[JWT] no JWT exp, schedule idle in ${remaining.inSeconds}s');
        _expiryTimer = Timer(remaining, _onIdleExpired);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[JWT] _checkTokenExpiry error: $e');
    }
  }

  /// Idle 10-minute expiry: session MUST end, require re-login.
  Future<void> _onIdleExpired() async {
    if (kDebugMode) debugPrint('[JWT] idle 10m session expired → hard logout, require re-login');
    AppLogger.debug('[JWT] idle 10m expired → hard logout');
    await _onSessionExpired();
  }

  /// Soft JWT expiry within the 10m window: try refresh WITHOUT extending idle.
  Future<void> _onSoftTokenExpired() async {
    // If idle already expired (with grace), hard logout instead of soft refresh
    final remaining = await SecureStorage.getRemainingIdleTime();
    if (remaining != null && remaining.inSeconds <= -10) {
      if (kDebugMode) debugPrint('[JWT] _onSoftTokenExpired but idle already expired → hard logout');
      await _onIdleExpired();
      return;
    }

    if (_isRefreshing) {
      if (kDebugMode) debugPrint('[JWT] _onSoftTokenExpired skipped (already refreshing)');
      return;
    }
    _isRefreshing = true;
    if (kDebugMode) debugPrint('[JWT] JWT soft expired → attempting soft refresh (idle ${remaining?.inSeconds}s left)...');
    AppLogger.debug('[JWT] soft JWT expired, attempting refresh within 10m idle window');
    try {
      final result = await _tryRefreshSession();
      if (!mounted) return;
      switch (result) {
        case SessionRefreshResult.success:
          if (kDebugMode) debugPrint('[JWT] soft refresh success → reschedule (absolute still governs)');
          AppLogger.debug('[JWT] soft refresh success, reschedule');
          // New JWT stored but absolute NOT extended → next timer still targets absolute expiry
          // Also need to ensure startedAt still preserved; saveTokens does not touch startedAt
          _scheduleExpiryCheck();
          break;
        case SessionRefreshResult.authRejected:
          if (kDebugMode) debugPrint('[JWT] soft refresh rejected → hard logout');
          AppLogger.debug('[JWT] soft refresh rejected → hard logout');
          await _onSessionExpired();
          break;
        case SessionRefreshResult.offline:
          if (kDebugMode) debugPrint('[JWT] offline during soft refresh → retry 30s, keep session until hard expiry');
          AppLogger.debug('[JWT] offline soft refresh, keep session, retry 30s');
          if (mounted) {
            _expiryTimer?.cancel();
            _expiryTimer = Timer(const Duration(seconds: 30), _onSoftTokenExpired);
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
  Future<SessionRefreshResult> _tryRefreshSession() => SessionRefresher.refresh();

  Future<void> _onSessionExpired() async {
    if (!state.isAuthenticated) {
      if (kDebugMode) debugPrint('[JWT] _onSessionExpired ignored (already logged out)');
      return;
    }
    // ── Stale event guard for multiple logins ───────────────────────────
    // If a sessionExpired event was emitted for an OLD session (e.g. first
    // login's 10m timer) but the user has already logged in again (second
    // login) and the new session is still valid, ignore the stale event.
    final remaining = await SecureStorage.getRemainingIdleTime();
    if (remaining != null && remaining.inSeconds > 10) {
      // New session still has >10s left → stale event, don't logout.
      if (kDebugMode) debugPrint('[JWT] _onSessionExpired ignored stale event, remaining ${remaining.inSeconds}s (second login still valid)');
      AppLogger.debug('[JWT] ignore stale sessionExpired, remaining ${remaining.inSeconds}s');
      return;
    }
    // Also check hasValidSession for legacy (no startedAt) – don't ignore if truly expired
    final hasSession = await SecureStorage.hasValidSession();
    if (remaining == null && hasSession) {
      // Legacy: no absolute timestamp, check JWT instead – if JWT still valid, stale
      final token = await SecureStorage.getAccessToken();
      if (token != null && !JwtParser.isExpired(token)) {
        if (kDebugMode) debugPrint('[JWT] _onSessionExpired ignored stale legacy event, JWT still valid');
        return;
      }
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

final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((
  ref,
) {
  return AuthStateNotifier()..initialize();
});
